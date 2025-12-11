import Foundation
import stellarsdk

class TransferFunction {
    func executeTransfer(
        request: TransferRequest,
        context: FunctionContext,
        nfcService: NFCService,
        blockchainService: BlockchainService,
        walletService: WalletService,
        stepCallback: @escaping (TransferView.TransferStep) -> Void
    ) async throws -> FunctionResult {
        let wallet = context.walletConnection
        
        guard request.from == wallet.address else {
            throw TransferError.incorrectOwner
        }
        
        stepCallback(.reading)
        
        // Read chip public key first to get nonce
        let chipPublicKey = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            nfcService.readPublicKey { result in
                continuation.resume(with: result)
            }
        }
        let publicKeyBytes = hexToBytes(chipPublicKey)
        guard publicKeyBytes.count == 65 else {
            throw TransferError.invalidPublicKey
        }
        
        // Get current nonce from contract
        var currentNonce: UInt32 = 0
        do {
            currentNonce = try await blockchainService.getNonce(
                contractId: request.contractId,
                publicKey: Data(publicKeyBytes)
            )
        } catch {
            // If get_nonce fails, default to 0
            // Nonce fetch failed, defaulting to 0 (first use)
            currentNonce = 0
        }
        
        // Use next nonce (must be greater than stored)
        let nonce = currentNonce + 1
        
        let sep53Result = try createSEP53Message(
            contractId: request.contractId,
            functionName: "transfer",
            args: [request.from, request.to, String(request.tokenId)] as [Any],
            nonce: nonce,
            networkPassphrase: context.networkPassphrase
        )
        
        stepCallback(.signing)
        let signatureResult = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(signatureBytes: Data, recoveryId: UInt8), Error>) in
            nfcService.signMessage(messageHash: sep53Result.messageHash) { result in
                switch result {
                case .success(let (r, s, recoveryId)):
                    let rBytes = hexToBytes(r)
                    let sBytes = hexToBytes(s)
                    var signatureBytes = Data()
                    signatureBytes.append(rBytes)
                    signatureBytes.append(sBytes)
                    guard signatureBytes.count == 64 else {
                        continuation.resume(throwing: TransferError.invalidSignature)
                        return
                    }
                    continuation.resume(returning: (signatureBytes: signatureBytes, recoveryId: UInt8(recoveryId)))
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
        
        stepCallback(.recovering)
        
        let recoveryId = try await determineRecoveryId(
            messageHash: sep53Result.messageHash,
            signature: signatureResult.signatureBytes,
            expectedPublicKey: chipPublicKey
        )
        
        stepCallback(.calling)
        
        // Get KeyPair for building transaction
        let sourceKeyPair = try stellarsdk.KeyPair(accountId: wallet.address)
        
        let transactionXdr = try await blockchainService.buildTransferTransaction(
            contractId: request.contractId,
            from: request.from,
            to: request.to,
            tokenId: request.tokenId,
            message: sep53Result.message,
            signature: signatureResult.signatureBytes,
            recoveryId: recoveryId,
            publicKey: publicKeyBytes,
            nonce: nonce,
            sourceAccount: wallet.address,
            sourceKeyPair: sourceKeyPair
        )
        
        let signedTx = try await walletService.signTransaction(
            transaction: transactionXdr,
            wallet: wallet
        )
        
        stepCallback(.confirming)
        
        let txHash = try await blockchainService.submitTransaction(signedTx)
        
        return FunctionResult(
            success: true,
            message: "Transfer successful. Transaction: \(txHash)",
            data: ["txHash": txHash, "tokenId": String(request.tokenId)]
        )
    }
    
}

enum TransferError: Error, LocalizedError {
    case noWallet
    case incorrectOwner
    case invalidPublicKey
    case invalidSignature
    case transactionFailed
    
    var errorDescription: String? {
        switch self {
        case .noWallet:
            return "No wallet connected"
        case .incorrectOwner:
            return "You are not the owner of this token"
        case .invalidPublicKey:
            return "Invalid public key format"
        case .invalidSignature:
            return "Invalid signature format"
        case .transactionFailed:
            return "Transaction failed"
        }
    }
}
