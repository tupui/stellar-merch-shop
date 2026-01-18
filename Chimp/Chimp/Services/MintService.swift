/**
 * Mint Service
 * Handles the complete mint flow with NFC chip authentication
 */

import Foundation
import CoreNFC
import stellarsdk
import OSLog

/// Result of a successful mint operation
struct MintResult {
    let transactionHash: String
    let tokenId: UInt64
}

final class MintService {
    private let blockchainService = BlockchainService()
    private let walletService = WalletService.shared
    private let config = AppConfig.shared

    /// Execute mint flow
    /// - Parameters:
    ///   - tag: NFCISO7816Tag for chip communication
    ///   - session: NFCTagReaderSession for session management
    ///   - keyIndex: Key index to use (default: 1)
    ///   - progressCallback: Optional callback for progress updates
    /// - Returns: Mint result with transaction hash and token ID
    /// - Throws: AppError if any step fails
    func executeMint(
        tag: NFCISO7816Tag,
        session: NFCTagReaderSession,
        keyIndex: UInt8 = 0x01,
        progressCallback: ((String) -> Void)? = nil
    ) async throws -> MintResult {
        guard let wallet = walletService.getStoredWallet() else {
            throw AppError.wallet(.noWallet)
        }

        let contractId = config.contractId
        guard !contractId.isEmpty else {
            Logger.logError("Contract ID is empty", category: .blockchain)
            throw AppError.validation("Contract ID not configured. Please set the contract ID in settings.")
        }

        guard config.validateContractId(contractId) else {
            Logger.logError("Invalid contract ID format: \(contractId)", category: .blockchain)
            throw AppError.validation("Invalid contract ID format. Contract ID must be 56 characters and start with 'C'.")
        }

        progressCallback?("Reading chip information...")
        let chipPublicKey = try await ChipOperations.readChipPublicKey(tag: tag, session: session, keyIndex: keyIndex)

        // Convert hex string to Data (65 bytes, uncompressed)
        guard let publicKeyData = Data(hexString: chipPublicKey),
              publicKeyData.count == 65,
              publicKeyData[0] == 0x04 else {
            throw AppError.crypto(.invalidKey("Invalid public key format from chip. Please ensure you're using a compatible NFC chip."))
        }

        let accountId = wallet.address

        progressCallback?("Preparing transaction...")
        let currentNonce: UInt32
        do {
            currentNonce = try await blockchainService.getNonce(
                contractId: config.contractId,
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
            contractId: config.contractId,
            functionName: "mint",
            args: [wallet.address],
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
                contractId: config.contractId,
                method: .mint,
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
        let (transaction, tokenId): (Transaction, UInt64)
        do {
            (transaction, tokenId) = try await blockchainService.buildMintTransaction(
                contractId: config.contractId,
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
        } catch let appError as AppError {
            if case .blockchain(.contract) = appError {
                throw appError
            }
            throw AppError.blockchain(.networkError("Failed to submit transaction: \(appError.localizedDescription)"))
        } catch {
            throw AppError.blockchain(.networkError("Failed to submit transaction: \(error.localizedDescription)"))
        }

        // Update NDEF data on chip with token ID
        progressCallback?("Completing operation...")
        do {
            let newUrl = "https://nft.chimpdao.xyz/\(config.contractId)/\(tokenId)"
            try await NDEFReader.writeNDEFUrl(tag: tag, session: session, url: newUrl)
        } catch {
            Logger.logWarning("Failed to update NDEF data on chip: \(error)", category: .nfc)
        }

        return MintResult(transactionHash: txHash, tokenId: tokenId)
    }

}

