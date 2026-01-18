/**
 * Transfer Service
 * Handles the complete transfer flow with NFC chip authentication
 */

import Foundation
import CoreNFC
import stellarsdk
import OSLog

/// Result of a successful transfer operation
struct TransferResult {
    let transactionHash: String
}

final class TransferService {
    private let blockchainService = BlockchainService()
    private let walletService = WalletService.shared
    private let config = AppConfig.shared

    /// Execute transfer flow
    /// - Parameters:
    ///   - tag: NFCISO7816Tag for chip communication
    ///   - session: NFCTagReaderSession for session management
    ///   - keyIndex: Key index to use (default: 1)
    ///   - recipientAddress: Address to transfer the token to
    ///   - tokenId: Token ID to transfer
    ///   - progressCallback: Optional callback for progress updates
    /// - Returns: Transfer result with transaction hash
    /// - Throws: AppError if any step fails
    func executeTransfer(
        tag: NFCISO7816Tag,
        session: NFCTagReaderSession,
        keyIndex: UInt8 = 0x01,
        recipientAddress: String,
        tokenId: UInt64,
        progressCallback: ((String) -> Void)? = nil
    ) async throws -> TransferResult {
        guard let wallet = walletService.getStoredWallet() else {
            throw AppError.wallet(.noWallet)
        }

        progressCallback?("Reading chip information...")
        let ndefUrl = try await NDEFReader.readNDEFUrl(tag: tag, session: session)
        guard let ndefUrl = ndefUrl, let contractId = NDEFReader.parseContractIdFromNDEFUrl(ndefUrl) else {
            throw AppError.validation("Invalid contract ID in NFC chip")
        }

        guard config.validateContractId(contractId) else {
            Logger.logError("Invalid contract ID format: \(contractId)", category: .blockchain)
            throw AppError.validation("Invalid contract ID format. Contract ID must be 56 characters and start with 'C'.")
        }

        guard config.validateStellarAddress(recipientAddress) else {
            Logger.logError("Invalid recipient address: \(recipientAddress)", category: .blockchain)
            throw AppError.validation("Invalid recipient address format. Please enter a valid Stellar address.")
        }

        progressCallback?("Reading chip information...")
        let chipPublicKey = try await ChipOperations.readChipPublicKey(tag: tag, session: session, keyIndex: keyIndex)

        guard let publicKeyData = Data(hexString: chipPublicKey),
              publicKeyData.count == 65,
              publicKeyData[0] == 0x04 else {
            throw AppError.crypto(.invalidKey("Invalid public key format from chip. Please ensure you're using a compatible NFC chip."))
        }

        let accountId = wallet.address

        progressCallback?("Validating chip ownership...")
        do {
            let expectedTokenId = try await blockchainService.getTokenId(
                contractId: contractId,
                publicKey: publicKeyData,
                accountId: accountId
            )
            guard expectedTokenId == tokenId else {
                throw AppError.validation("This NFC chip does not correspond to token ID \(tokenId). Expected token ID: \(expectedTokenId)")
            }
        } catch let error as AppError {
            if case .blockchain(.contract(.nonExistentToken)) = error {
                throw AppError.validation("This NFC chip is not registered with the contract")
            } else {
                // Re-throw other errors
                throw error
            }
        }

        progressCallback?("Preparing transaction...")
        let currentNonce: UInt32
        do {
            currentNonce = try await blockchainService.getNonce(
                contractId: contractId,
                publicKey: publicKeyData,
                accountId: accountId
            )
        } catch let appError as AppError {
            if case .blockchain(.contract) = appError {
                throw appError
            }
            Logger.logError("Failed to get nonce: \(appError)", category: .blockchain)
            throw AppError.nfc(.chipError("Failed to get nonce: \(appError.localizedDescription)"))
        } catch {
            Logger.logError("Failed to get nonce: \(error)", category: .blockchain)
            throw AppError.nfc(.chipError("Failed to get nonce: \(error.localizedDescription)"))
        }
        let nonce = currentNonce + 1

        let (message, messageHash) = try CryptoUtils.createSEP53Message(
            contractId: contractId,
            functionName: "transfer",
            args: [wallet.address, recipientAddress, String(tokenId)],
            nonce: nonce,
            networkPassphrase: config.networkPassphrase
        )

        progressCallback?("Signing transaction...")
        let signatureComponents = try await ChipOperations.signWithChip(
            tag: tag,
            session: session,
            messageHash: messageHash,
            keyIndex: keyIndex
        )

        let originalS = signatureComponents.s
        let normalizedS = CryptoUtils.normalizeS(originalS)

        var signature = Data()
        signature.append(signatureComponents.r)
        signature.append(normalizedS)

        guard signature.count == 64 else {
            throw AppError.crypto(.invalidSignature)
        }

        let sourceKeyPair = try KeyPair(accountId: wallet.address)
        
        let recoveryId: UInt32
        do {
            recoveryId = try await blockchainService.determineRecoveryId(
                contractId: contractId,
                method: .transfer(from: wallet.address, to: recipientAddress, tokenId: tokenId),
                message: message,
                signature: signature,
                publicKey: publicKeyData,
                nonce: nonce,
                sourceKeyPair: sourceKeyPair
            )
        } catch {
            Logger.logError("Failed to determine recovery ID: \(error)", category: .blockchain)
            throw AppError.crypto(.verificationFailed)
        }

        progressCallback?("Building transaction...")
        let transaction: Transaction
        do {
            transaction = try await blockchainService.buildTransferTransaction(
                contractId: contractId,
                from: wallet.address,
                to: recipientAddress,
                tokenId: tokenId,
                message: message,
                signature: signature,
                recoveryId: recoveryId,
                publicKey: publicKeyData,
                nonce: nonce,
                sourceKeyPair: sourceKeyPair
            )
        } catch let appError as AppError {
            if case .blockchain(.contract) = appError {
                throw appError
            }
            Logger.logError("ERROR building transaction: \(appError)", category: .blockchain)
            throw AppError.blockchain(.networkError("Failed to build transaction: \(appError.localizedDescription)"))
        } catch {
            Logger.logError("ERROR building transaction: \(error)", category: .blockchain)
            throw AppError.blockchain(.networkError("Failed to build transaction: \(error.localizedDescription)"))
        }

        progressCallback?("Signing transaction...")
        try await walletService.signTransaction(transaction)

        progressCallback?("Processing on blockchain network...")
        let txHash: String
        do {
            txHash = try await blockchainService.submitTransaction(transaction, progressCallback: progressCallback)
            Logger.logInfo("Transfer transaction submitted successfully: \(txHash)", category: .blockchain)
        } catch let appError as AppError {
            if case .blockchain(.contract(let contractError)) = appError {
                Logger.logError("Transfer failed with contract error: \(contractError) (code: \(contractError.code))", category: .blockchain)
                Logger.logError("Transfer context: from=\(wallet.address), to=\(recipientAddress), tokenId=\(tokenId)", category: .blockchain)
                if case .tokenAlreadyMinted = contractError {
                    Logger.logError("WARNING: TokenAlreadyMinted (210) occurred during transfer - this should not happen!", category: .blockchain)
                }
                throw appError
            }
            Logger.logError("Transfer failed with error: \(appError)", category: .blockchain)
            throw AppError.blockchain(.networkError("Failed to submit transaction: \(appError.localizedDescription)"))
        } catch {
            Logger.logError("Transfer failed with unexpected error: \(error)", category: .blockchain)
            throw AppError.blockchain(.networkError("Failed to submit transaction: \(error.localizedDescription)"))
        }

        return TransferResult(transactionHash: txHash)
    }

}

