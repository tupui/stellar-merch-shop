/**
 * NFT Service
 * Handles claim, transfer, and mint operations with NFC chip authentication
 */

import Foundation
import CoreNFC
import stellarsdk
import OSLog

/// Result of a successful claim operation
struct ClaimResult {
    let transactionHash: String
    let tokenId: UInt64
    let contractId: String
}

/// Result of a successful transfer operation
struct TransferResult {
    let transactionHash: String
}

/// Result of a successful mint operation
struct MintResult {
    let transactionHash: String
    let tokenId: UInt64
}

final class NFTService {
    private let blockchainService = BlockchainService()
    private let walletService = WalletService.shared
    private let config = AppConfig.shared
    
    // MARK: - Public Methods
    
    /// Execute claim flow
    /// - Parameters:
    ///   - tag: NFCISO7816Tag for chip communication
    ///   - session: NFCTagReaderSession for session management
    ///   - keyIndex: Key index to use (default: 1)
    ///   - progressCallback: Optional callback for progress updates
    /// - Returns: Claim result with transaction hash and token ID
    /// - Throws: AppError if any step fails
    func executeClaim(
        tag: NFCISO7816Tag,
        session: NFCTagReaderSession,
        keyIndex: UInt8 = 0x01,
        progressCallback: ((String) -> Void)? = nil
    ) async throws -> ClaimResult {
        guard let wallet = walletService.getStoredWallet() else {
            throw AppError.wallet(.noWallet)
        }

        progressCallback?("Reading chip information...")
        let (contractId, publicKeyData) = try await readChipAndGetContractId(
            tag: tag,
            session: session,
            keyIndex: keyIndex,
            progressCallback: progressCallback
        )

        let accountId = wallet.address
        
        progressCallback?("Preparing transaction...")
        let nonce = try await getNonce(
            contractId: contractId,
            publicKey: publicKeyData,
            accountId: accountId
        )
        
        let (message, messageHash) = try CryptoUtils.createSEP53Message(
            contractId: contractId,
            functionName: "claim",
            args: [wallet.address],
            nonce: nonce,
            networkPassphrase: config.networkPassphrase
        )
        
        progressCallback?("Signing transaction...")
        let signature = try await createSignature(
            tag: tag,
            session: session,
            messageHash: messageHash,
            keyIndex: keyIndex
        )

        let sourceKeyPair = try KeyPair(accountId: wallet.address)
        
        progressCallback?("Building transaction...")
        let (transaction, tokenId) = try await determineRecoveryIdAndBuildTransaction(
            contractId: contractId,
            method: .claim(claimant: wallet.address),
            message: message,
            signature: signature,
            publicKey: publicKeyData,
            nonce: nonce,
            sourceKeyPair: sourceKeyPair,
            progressCallback: progressCallback
        )

        progressCallback?("Signing transaction...")
        try await walletService.signTransaction(transaction)

        progressCallback?("Processing on blockchain network...")
        let txHash = try await submitTransaction(transaction, progressCallback: progressCallback)

        // Update NDEF data on chip with token ID
        progressCallback?("Completing operation...")
        do {
            let newUrl = "https://nft.chimpdao.xyz/\(contractId)/\(tokenId)"
            try await NDEFReader.writeNDEFUrl(tag: tag, session: session, url: newUrl)
        } catch {
            Logger.logWarning("Failed to update NDEF data on chip: \(error)", category: .nfc)
        }

        return ClaimResult(transactionHash: txHash, tokenId: tokenId, contractId: contractId)
    }
    
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

        guard config.validateStellarAddress(recipientAddress) else {
            Logger.logError("Invalid recipient address: \(recipientAddress)", category: .blockchain)
            throw AppError.validation("Invalid recipient address format. Please enter a valid Stellar address.")
        }

        progressCallback?("Reading chip information...")
        let (contractId, publicKeyData) = try await readChipAndGetContractId(
            tag: tag,
            session: session,
            keyIndex: keyIndex,
            progressCallback: progressCallback
        )

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
                throw error
            }
        }

        progressCallback?("Preparing transaction...")
        let nonce = try await getNonce(
            contractId: contractId,
            publicKey: publicKeyData,
            accountId: accountId
        )

        let (message, messageHash) = try CryptoUtils.createSEP53Message(
            contractId: contractId,
            functionName: "transfer",
            args: [wallet.address, recipientAddress, String(tokenId)],
            nonce: nonce,
            networkPassphrase: config.networkPassphrase
        )

        progressCallback?("Signing transaction...")
        let signature = try await createSignature(
            tag: tag,
            session: session,
            messageHash: messageHash,
            keyIndex: keyIndex
        )

        let sourceKeyPair = try KeyPair(accountId: wallet.address)
        
        progressCallback?("Building transaction...")
        let transaction = try await determineRecoveryIdAndBuildTransferTransaction(
            contractId: contractId,
            from: wallet.address,
            to: recipientAddress,
            tokenId: tokenId,
            message: message,
            signature: signature,
            publicKey: publicKeyData,
            nonce: nonce,
            sourceKeyPair: sourceKeyPair,
            progressCallback: progressCallback
        )

        progressCallback?("Signing transaction...")
        try await walletService.signTransaction(transaction)

        progressCallback?("Processing on blockchain network...")
        let txHash = try await submitTransaction(transaction, progressCallback: progressCallback)
        Logger.logInfo("Transfer transaction submitted successfully: \(txHash)", category: .blockchain)

        return TransferResult(transactionHash: txHash)
    }
    
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
        let publicKeyData = try await getChipPublicKey(
            tag: tag,
            session: session,
            keyIndex: keyIndex
        )

        let accountId = wallet.address

        progressCallback?("Preparing transaction...")
        let nonce = try await getNonce(
            contractId: contractId,
            publicKey: publicKeyData,
            accountId: accountId
        )

        let (message, messageHash) = try CryptoUtils.createSEP53Message(
            contractId: contractId,
            functionName: "mint",
            args: [wallet.address],
            nonce: nonce,
            networkPassphrase: config.networkPassphrase
        )

        progressCallback?("Signing transaction...")
        let signature = try await createSignature(
            tag: tag,
            session: session,
            messageHash: messageHash,
            keyIndex: keyIndex
        )

        let sourceKeyPair = try KeyPair(accountId: wallet.address)
        
        progressCallback?("Building transaction...")
        let (transaction, tokenId) = try await determineRecoveryIdAndBuildTransaction(
            contractId: contractId,
            method: .mint,
            message: message,
            signature: signature,
            publicKey: publicKeyData,
            nonce: nonce,
            sourceKeyPair: sourceKeyPair,
            progressCallback: progressCallback
        )

        progressCallback?("Signing transaction...")
        try await walletService.signTransaction(transaction)

        progressCallback?("Processing on blockchain network...")
        let txHash = try await submitTransaction(transaction, progressCallback: progressCallback)

        // Update NDEF data on chip with token ID
        progressCallback?("Completing operation...")
        do {
            let newUrl = "https://nft.chimpdao.xyz/\(contractId)/\(tokenId)"
            try await NDEFReader.writeNDEFUrl(tag: tag, session: session, url: newUrl)
        } catch {
            Logger.logWarning("Failed to update NDEF data on chip: \(error)", category: .nfc)
        }

        return MintResult(transactionHash: txHash, tokenId: tokenId)
    }
    
    // MARK: - Private Helper Methods
    
    /// Read chip NDEF and public key, return contract ID and public key data
    private func readChipAndGetContractId(
        tag: NFCISO7816Tag,
        session: NFCTagReaderSession,
        keyIndex: UInt8,
        progressCallback: ((String) -> Void)?
    ) async throws -> (contractId: String, publicKeyData: Data) {
        let ndefUrl = try await NDEFReader.readNDEFUrl(tag: tag, session: session)
        guard let ndefUrl = ndefUrl, let contractId = NDEFReader.parseContractIdFromNDEFUrl(ndefUrl) else {
            throw AppError.validation("Invalid contract ID in NFC chip")
        }

        guard config.validateContractId(contractId) else {
            Logger.logError("Invalid contract ID format: \(contractId)", category: .blockchain)
            throw AppError.validation("Invalid contract ID format. Contract ID must be 56 characters and start with 'C'.")
        }
        
        progressCallback?("Reading chip information...")
        let publicKeyData = try await getChipPublicKey(tag: tag, session: session, keyIndex: keyIndex)
        
        return (contractId, publicKeyData)
    }
    
    /// Read chip public key and validate format
    private func getChipPublicKey(
        tag: NFCISO7816Tag,
        session: NFCTagReaderSession,
        keyIndex: UInt8
    ) async throws -> Data {
        let chipPublicKey = try await ChipOperations.readChipPublicKey(tag: tag, session: session, keyIndex: keyIndex)
        
        guard let publicKeyData = Data(hexString: chipPublicKey),
              publicKeyData.count == 65,
              publicKeyData[0] == 0x04 else {
            throw AppError.crypto(.invalidKey("Invalid public key format from chip. Please ensure you're using a compatible NFC chip."))
        }
        
        return publicKeyData
    }
    
    /// Get nonce for chip public key
    private func getNonce(
        contractId: String,
        publicKey: Data,
        accountId: String
    ) async throws -> UInt32 {
        let currentNonce = try await blockchainService.getNonce(
            contractId: contractId,
            publicKey: publicKey,
            accountId: accountId
        )
        return currentNonce + 1
    }
    
    /// Create signature from chip
    private func createSignature(
        tag: NFCISO7816Tag,
        session: NFCTagReaderSession,
        messageHash: Data,
        keyIndex: UInt8
    ) async throws -> Data {
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
        
        return signature
    }
    
    /// Determine recovery ID and build transfer transaction
    private func determineRecoveryIdAndBuildTransferTransaction(
        contractId: String,
        from: String,
        to: String,
        tokenId: UInt64,
        message: Data,
        signature: Data,
        publicKey: Data,
        nonce: UInt32,
        sourceKeyPair: KeyPair,
        progressCallback: ((String) -> Void)?
    ) async throws -> Transaction {
        let recoveryId = try await blockchainService.determineRecoveryId(
            contractId: contractId,
            method: .transfer(from: from, to: to, tokenId: tokenId),
            message: message,
            signature: signature,
            publicKey: publicKey,
            nonce: nonce,
            sourceKeyPair: sourceKeyPair
        )
        
        let transaction = try await blockchainService.buildTransferTransaction(
            contractId: contractId,
            from: from,
            to: to,
            tokenId: tokenId,
            message: message,
            signature: signature,
            recoveryId: recoveryId,
            publicKey: publicKey,
            nonce: nonce,
            sourceKeyPair: sourceKeyPair
        )
        return transaction
    }
    
    /// Determine recovery ID and build transaction (returns transaction and token ID for claim/mint)
    private func determineRecoveryIdAndBuildTransaction(
        contractId: String,
        method: BlockchainService.ContractMethod,
        message: Data,
        signature: Data,
        publicKey: Data,
        nonce: UInt32,
        sourceKeyPair: KeyPair,
        progressCallback: ((String) -> Void)?
    ) async throws -> (Transaction, UInt64) {
        let recoveryId = try await blockchainService.determineRecoveryId(
            contractId: contractId,
            method: method,
            message: message,
            signature: signature,
            publicKey: publicKey,
            nonce: nonce,
            sourceKeyPair: sourceKeyPair
        )
        switch method {
        case .claim(let claimant):
            let (transaction, tokenId) = try await blockchainService.buildClaimTransaction(
                contractId: contractId,
                claimant: claimant,
                message: message,
                signature: signature,
                recoveryId: recoveryId,
                publicKey: publicKey,
                nonce: nonce,
                sourceAccount: claimant,
                sourceKeyPair: sourceKeyPair
            )
            return (transaction, tokenId)
            
        case .mint:
            let (transaction, tokenId) = try await blockchainService.buildMintTransaction(
                contractId: contractId,
                message: message,
                signature: signature,
                recoveryId: recoveryId,
                publicKey: publicKey,
                nonce: nonce,
                sourceKeyPair: sourceKeyPair
            )
            return (transaction, tokenId)
            
        default:
            throw AppError.unexpected("Invalid method type for buildTransactionWithTokenId")
        }
    }
    
    /// Submit transaction to blockchain
    private func submitTransaction(
        _ transaction: Transaction,
        progressCallback: ((String) -> Void)?
    ) async throws -> String {
        let txHash = try await blockchainService.submitTransaction(transaction, progressCallback: progressCallback)
        return txHash
    }
}
