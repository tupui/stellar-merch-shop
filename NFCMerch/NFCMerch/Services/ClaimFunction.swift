import Foundation
import stellarsdk

class ClaimFunction {
    func executeClaim(
        contractId: String,
        context: FunctionContext,
        nfcService: NFCService,
        blockchainService: BlockchainService,
        walletService: WalletService,
        stepCallback: @escaping (ClaimView.ClaimStep) -> Void
    ) async throws -> FunctionResult {
        let wallet = context.walletConnection
        
        stepCallback(.reading)
        
        // Read chip public key first to get nonce
        let chipPublicKey = try await NFCServiceHelper.readChipPublicKey(nfcService: nfcService)
        let publicKeyBytes = hexToBytes(chipPublicKey)
        guard publicKeyBytes.count == 65 else {
            throw ClaimError.invalidPublicKey
        }
        
        // Get current nonce from contract
        var currentNonce: UInt32 = 0
        do {
            currentNonce = try await blockchainService.getNonce(
                contractId: contractId,
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
            contractId: contractId,
            functionName: "claim",
            args: [wallet.address] as [Any],
            nonce: nonce,
            networkPassphrase: context.networkPassphrase
        )
        
        stepCallback(.signing)
        let signatureResult = try await NFCServiceHelper.signWithChip(
            nfcService: nfcService,
            messageHash: sep53Result.messageHash
        )
        
        stepCallback(.recovering)
        
        let recoveryId = try await determineRecoveryId(
            messageHash: sep53Result.messageHash,
            signature: signatureResult.signatureBytes,
            expectedPublicKey: chipPublicKey
        )
        
        stepCallback(.calling)
        
        // Get KeyPair for building transaction
        let sourceKeyPair: stellarsdk.KeyPair
        if case .manual = wallet.type {
            let dummyTx = Data("dummy".utf8)
            let _ = try await walletService.signTransaction(transaction: dummyTx, wallet: wallet)
            sourceKeyPair = try stellarsdk.KeyPair(accountId: wallet.address)
        } else {
            sourceKeyPair = try stellarsdk.KeyPair(accountId: wallet.address)
        }
        
        let transactionXdr = try await blockchainService.buildClaimTransaction(
            contractId: contractId,
            claimant: wallet.address,
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
            message: "Claim successful. Transaction: \(txHash)",
            data: ["txHash": txHash]
        )
    }
    
}

enum ClaimError: Error, LocalizedError {
    case noWallet
    case invalidPublicKey
    case invalidSignature
    case transactionFailed
    
    var errorDescription: String? {
        switch self {
        case .noWallet:
            return "No wallet connected"
        case .invalidPublicKey:
            return "Invalid public key format"
        case .invalidSignature:
            return "Invalid signature format"
        case .transactionFailed:
            return "Transaction failed"
        }
    }
}
