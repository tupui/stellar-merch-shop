/**
 * Claim Service
 * Handles the complete claim flow with NFC chip authentication
 */

import Foundation
import CoreNFC
import stellarsdk

class ClaimService {
    private let blockchainService = BlockchainService()
    private let walletService = WalletService()
    private let config = AppConfig.shared
    
    /// Execute claim flow
    /// - Parameters:
    ///   - tag: NFCISO7816Tag for chip communication
    ///   - session: NFCTagReaderSession for session management
    ///   - keyIndex: Key index to use (default: 1)
    ///   - progressCallback: Optional callback for progress updates
    /// - Returns: Transaction hash
    /// - Throws: ClaimError if any step fails
    func executeClaim(
        tag: NFCISO7816Tag,
        session: NFCTagReaderSession,
        keyIndex: UInt8 = 0x01,
        progressCallback: ((String) -> Void)? = nil
    ) async throws -> String {
        guard let wallet = walletService.getStoredWallet() else {
            throw ClaimError.noWallet
        }
        
        let contractId = config.contractId
        guard !contractId.isEmpty else {
            print("ClaimService: ERROR: Contract ID is empty")
            throw ClaimError.noContractId
        }
        
        print("ClaimService: Contract ID: \(contractId)")
        print("ClaimService: Contract ID length: \(contractId.count)")
        print("ClaimService: Wallet address: \(wallet.address)")
        
        // Step 1: Read chip public key
        progressCallback?("Reading chip public key...")
        let chipPublicKey = try await readChipPublicKey(tag: tag, session: session, keyIndex: keyIndex)
        
        // Convert hex string to Data (65 bytes, uncompressed)
        guard let publicKeyData = Data(hexString: chipPublicKey),
              publicKeyData.count == 65,
              publicKeyData[0] == 0x04 else {
            throw ClaimError.invalidPublicKey
        }
        
        // Step 2: Get source keypair for transaction building
        let secureStorage = SecureKeyStorage()
        guard let privateKey = try secureStorage.loadPrivateKey() else {
            throw ClaimError.noWallet
        }
        let sourceKeyPair = try KeyPair(secretSeed: privateKey)
        print("ClaimService: Source account: \(sourceKeyPair.accountId)")
        
        // Step 3: Get nonce from contract
        progressCallback?("Getting nonce from contract...")
        print("ClaimService: Getting nonce for contract: \(config.contractId)")
        let currentNonce: UInt32
        do {
            currentNonce = try await blockchainService.getNonce(
                contractId: config.contractId,
                publicKey: publicKeyData,
                sourceKeyPair: sourceKeyPair
            )
        } catch {
            print("ClaimService: ERROR getting nonce: \(error)")
            throw ClaimError.chipReadFailed("Failed to get nonce: \(error.localizedDescription)")
        }
        let nonce = currentNonce + 1
        print("ClaimService: Using nonce: \(nonce) (previous: \(currentNonce))")
        
        // Step 4: Create SEP-53 message
        progressCallback?("Creating authentication message...")
        let (message, messageHash) = try CryptoUtils.createSEP53Message(
            contractId: config.contractId,
            functionName: "claim",
            args: [wallet.address],
            nonce: nonce,
            networkPassphrase: config.networkPassphrase
        )
        
        // Step 4: Sign with chip
        progressCallback?("Signing with chip...")
        let signatureComponents = try await signWithChip(
            tag: tag,
            session: session,
            messageHash: messageHash,
            keyIndex: keyIndex
        )
        
        // Step 5: Normalize S value
        let normalizedS = CryptoUtils.normalizeS(signatureComponents.s)
        
        // Step 6: Build signature (r + normalized s)
        var signature = Data()
        signature.append(signatureComponents.r)
        signature.append(normalizedS)
        
        guard signature.count == 64 else {
            throw ClaimError.invalidSignature
        }
        
        // Step 8: Try recovery IDs (start with 1, then 0, 2, 3)
        let recoveryIdsToTry: [UInt32] = [1, 0, 2, 3]
        var lastError: Error?
        
        for recoveryId in recoveryIdsToTry {
            do {
                progressCallback?("Trying recovery ID \(recoveryId)...")
                
                // Source keypair already obtained in Step 2
                
                // Build transaction
                print("ClaimService: Building transaction with recovery ID \(recoveryId)...")
                let transactionXdr: Data
                do {
                    transactionXdr = try await blockchainService.buildClaimTransaction(
                        contractId: config.contractId,
                        claimant: wallet.address,
                        message: message,
                        signature: signature,
                        recoveryId: recoveryId,
                        publicKey: publicKeyData,
                        nonce: nonce,
                        sourceAccount: wallet.address,
                        sourceKeyPair: sourceKeyPair
                    )
                    print("ClaimService: Transaction built successfully")
                } catch {
                    print("ClaimService: ERROR building transaction: \(error)")
                    if let sorobanError = error as? SorobanRpcRequestError {
                        print("ClaimService: SorobanRpcRequestError details: \(sorobanError)")
                    }
                    throw ClaimError.chipSignFailed("Failed to build transaction: \(error.localizedDescription)")
                }
                
                // Sign transaction
                progressCallback?("Signing transaction...")
                let signedTx = try await walletService.signTransaction(transactionXdr)
                
                // Submit transaction
                progressCallback?("Submitting transaction...")
                let txHash = try await blockchainService.submitTransaction(signedTx)
                
                return txHash
            } catch {
                print("ClaimService: ERROR with recovery ID \(recoveryId): \(error)")
                if let sorobanError = error as? SorobanRpcRequestError {
                    print("ClaimService: SorobanRpcRequestError: \(sorobanError)")
                }
                lastError = error
                // If transaction was rejected due to invalid signature, try next recovery ID
                if case BlockchainError.transactionRejected = error {
                    print("ClaimService: Transaction rejected, trying next recovery ID...")
                    continue
                }
                // For RPC errors, also try next recovery ID (might be signature issue)
                if error is SorobanRpcRequestError {
                    print("ClaimService: RPC error, trying next recovery ID...")
                    continue
                }
                // For other errors, rethrow
                throw error
            }
        }
        
        // If all recovery IDs failed, throw error
        throw ClaimError.invalidRecoveryId(lastError?.localizedDescription ?? "All recovery IDs failed")
    }
    
    /// Read public key from chip
    private func readChipPublicKey(tag: NFCISO7816Tag, session: NFCTagReaderSession, keyIndex: UInt8) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let commandHandler = BlockchainCommandHandler(tag_iso7816: tag, reader_session: session)
            commandHandler.ActionGetKey(key_index: keyIndex) { success, response, error, session in
                if success, let response = response, response.count >= 73 {
                    // Extract public key (skip first 9 bytes: 4 bytes global counter + 4 bytes signature counter + 1 byte 0x04)
                    let publicKeyData = response.subdata(in: 9..<73) // 64 bytes of public key
                    // Add 0x04 prefix for uncompressed format
                    var fullPublicKey = Data([0x04])
                    fullPublicKey.append(publicKeyData)
                    let publicKeyHex = fullPublicKey.map { String(format: "%02x", $0) }.joined()
                    continuation.resume(returning: publicKeyHex)
                } else {
                    continuation.resume(throwing: ClaimError.chipReadFailed(error ?? "Unknown error"))
                }
            }
        }
    }
    
    /// Sign message with chip
    private func signWithChip(tag: NFCISO7816Tag, session: NFCTagReaderSession, messageHash: Data, keyIndex: UInt8) async throws -> SignatureComponents {
        guard messageHash.count == 32 else {
            throw ClaimError.invalidMessageHash
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let commandHandler = BlockchainCommandHandler(tag_iso7816: tag, reader_session: session)
            commandHandler.ActionGenerateSignature(key_index: keyIndex, message_digest: messageHash) { success, response, error, session in
                if success, let response = response, response.count >= 8 {
                    // Response format: 4 bytes global counter + 4 bytes key counter + DER signature
                    let derSignature = response.subdata(in: 8..<response.count)
                    
                    do {
                        let components = try DERSignatureParser.parse(derSignature)
                        continuation.resume(returning: components)
                    } catch {
                        continuation.resume(throwing: ClaimError.signatureParseFailed(error.localizedDescription))
                    }
                } else {
                    continuation.resume(throwing: ClaimError.chipSignFailed(error ?? "Unknown error"))
                }
            }
        }
    }
}

enum ClaimError: Error, LocalizedError {
    case noWallet
    case noContractId
    case invalidPublicKey
    case invalidMessageHash
    case chipReadFailed(String)
    case chipSignFailed(String)
    case signatureParseFailed(String)
    case invalidSignature
    case invalidRecoveryId(String)
    
    var errorDescription: String? {
        switch self {
        case .noWallet:
            return "No wallet configured. Please login first."
        case .noContractId:
            return "Contract ID not configured. Please set it in settings."
        case .invalidPublicKey:
            return "Invalid public key format from chip"
        case .invalidMessageHash:
            return "Invalid message hash (must be 32 bytes)"
        case .chipReadFailed(let message):
            return "Failed to read chip: \(message)"
        case .chipSignFailed(let message):
            return "Failed to sign with chip: \(message)"
        case .signatureParseFailed(let message):
            return "Failed to parse signature: \(message)"
        case .invalidSignature:
            return "Invalid signature format"
        case .invalidRecoveryId(let message):
            return "Could not determine recovery ID: \(message)"
        }
    }
}
