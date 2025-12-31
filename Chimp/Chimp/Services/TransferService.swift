/**
 * Transfer Service
 * Handles the complete transfer flow with NFC chip authentication
 */

import Foundation
import CoreNFC
import stellarsdk

/// Result of a successful transfer operation
struct TransferResult {
    let transactionHash: String
}

class TransferService {
    private let blockchainService = BlockchainService()
    private let walletService = WalletService()
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

        // Step 1: Read contract ID from chip's NDEF
        progressCallback?("Reading chip data...")
        let ndefUrl = try await readNDEFUrl(tag: tag, session: session)
        guard let ndefUrl = ndefUrl, let contractId = parseContractIdFromNDEFUrl(ndefUrl) else {
            throw AppError.validation("Invalid contract ID in NFC chip")
        }

        print("TransferService: Contract ID from chip: \(contractId)")

        // Validate contract ID format
        guard config.validateContractId(contractId) else {
            print("TransferService: ERROR: Invalid contract ID format: \(contractId)")
            print("TransferService: Contract ID should be 56 characters, start with 'C'")
            throw AppError.validation("Invalid contract ID format. Contract ID must be 56 characters and start with 'C'.")
        }

        // Validate recipient address
        guard config.validateStellarAddress(recipientAddress) else {
            print("TransferService: ERROR: Invalid recipient address: \(recipientAddress)")
            throw AppError.validation("Invalid recipient address format. Please enter a valid Stellar address.")
        }

        print("TransferService: Contract ID: \(contractId)")
        print("TransferService: Contract ID length: \(contractId.count)")
        print("TransferService: Wallet address: \(wallet.address)")
        print("TransferService: Recipient address: \(recipientAddress)")
        print("TransferService: Token ID: \(tokenId)")

        // Step 1: Read chip public key
        progressCallback?("Reading chip public key...")
        let chipPublicKey = try await readChipPublicKey(tag: tag, session: session, keyIndex: keyIndex)

        // Convert hex string to Data (65 bytes, uncompressed)
        guard let publicKeyData = Data(hexString: chipPublicKey),
              publicKeyData.count == 65,
              publicKeyData[0] == 0x04 else {
            throw AppError.crypto(.invalidKey("Invalid public key format from chip. Please ensure you're using a compatible NFC chip."))
        }

        // Step 2: Get source keypair for transaction building
        let secureStorage = SecureKeyStorage()
        guard let privateKey = try secureStorage.loadPrivateKey() else {
            throw AppError.wallet(.noWallet)
        }
        let sourceKeyPair = try KeyPair(secretSeed: privateKey)

        // Step 3: Validate that the chip's public key corresponds to the token ID
        progressCallback?("Validating chip ownership...")
        print("TransferService: Validating that chip corresponds to token ID \(tokenId)")
        do {
            let expectedTokenId = try await blockchainService.getTokenId(
                contractId: config.contractId,
                publicKey: publicKeyData,
                sourceKeyPair: sourceKeyPair
            )
            guard expectedTokenId == tokenId else {
                throw AppError.validation("This NFC chip does not correspond to token ID \(tokenId). Expected token ID: \(expectedTokenId)")
            }
            print("TransferService: Chip validation successful - corresponds to token ID \(tokenId)")
        } catch let error as AppError {
            if case .blockchain(.contract(.nonExistentToken)) = error {
                throw AppError.validation("This NFC chip is not registered with the contract")
            } else {
                // Re-throw other errors
                throw error
            }
        }

        // Step 4: Get nonce from contract
        progressCallback?("Getting nonce from contract...")
        print("TransferService: Getting nonce for contract: \(config.contractId)")
        let currentNonce: UInt32
        do {
            currentNonce = try await blockchainService.getNonce(
                contractId: config.contractId,
                publicKey: publicKeyData,
                sourceKeyPair: sourceKeyPair
            )
        } catch let appError as AppError {
            // Re-throw contract errors as-is so ViewController can handle them specifically
            if case .blockchain(.contract) = appError {
                throw appError
            }
            print("TransferService: ERROR getting nonce: \(appError)")
            throw AppError.nfc(.chipError("Failed to get nonce: \(appError.localizedDescription)"))
        } catch {
            print("TransferService: ERROR getting nonce: \(error)")
            throw AppError.nfc(.chipError("Failed to get nonce: \(error.localizedDescription)"))
        }
        let nonce = currentNonce + 1
        print("TransferService: Using nonce: \(nonce) (previous: \(currentNonce))")

        // Step 4: Create SEP-53 message
        progressCallback?("Creating authentication message...")
        let (message, messageHash) = try CryptoUtils.createSEP53Message(
            contractId: config.contractId,
            functionName: "transfer",
            args: [wallet.address, recipientAddress, String(tokenId)],
            nonce: nonce,
            networkPassphrase: config.networkPassphrase
        )

        print("TransferService: SEP-53 message length: \(message.count)")
        print("TransferService: SEP-53 message (hex): \(message.map { String(format: "%02x", $0) }.joined())")
        print("TransferService: Message hash (hex): \(messageHash.map { String(format: "%02x", $0) }.joined())")

        // Step 5: Sign with chip
        progressCallback?("Signing with chip...")
        let signatureComponents = try await signWithChip(
            tag: tag,
            session: session,
            messageHash: messageHash,
            keyIndex: keyIndex
        )

        // Step 6: Normalize S value (required by Soroban's secp256k1_recover)
        let originalS = signatureComponents.s
        let normalizedS = CryptoUtils.normalizeS(originalS)

        // Debug: Log signature components
        let rHex = signatureComponents.r.map { String(format: "%02x", $0) }.joined()
        let sOriginalHex = originalS.map { String(format: "%02x", $0) }.joined()
        let sNormalizedHex = normalizedS.map { String(format: "%02x", $0) }.joined()
        print("TransferService: Signature r (hex): \(rHex)")
        print("TransferService: Signature s original (hex): \(sOriginalHex)")
        print("TransferService: Signature s normalized (hex): \(sNormalizedHex)")
        if originalS != normalizedS {
            print("TransferService: S value was normalized (s > half_order)")
        } else {
            print("TransferService: S value already normalized (s <= half_order)")
        }

        // Step 7: Build signature (r + normalized s) - 64 bytes total
        var signature = Data()
        signature.append(signatureComponents.r)
        signature.append(normalizedS)

        guard signature.count == 64 else {
            throw AppError.crypto(.invalidSignature)
        }

        let signatureHex = signature.map { String(format: "%02x", $0) }.joined()
        print("TransferService: Final signature (r+s, hex): \(signatureHex)")

        // Step 8: Determine recovery ID offline
        progressCallback?("Determining recovery ID...")
        print("TransferService: Determining recovery ID offline...")
        let recoveryId: UInt32
        do {
            recoveryId = try await blockchainService.determineRecoveryId(
                contractId: config.contractId,
                claimant: wallet.address,
                message: message,
                signature: signature,
                publicKey: publicKeyData,
                nonce: nonce,
                sourceKeyPair: sourceKeyPair
            )
            print("TransferService: Recovery ID determined: \(recoveryId)")
        } catch {
            print("TransferService: ERROR determining recovery ID: \(error)")
            throw AppError.crypto(.verificationFailed)
        }

        // Step 9: Build transaction with the correct recovery ID
        progressCallback?("Building transaction...")
        print("TransferService: Building transaction with recovery ID \(recoveryId)...")
        let transaction: Transaction
        do {
            transaction = try await blockchainService.buildTransferTransaction(
                contractId: config.contractId,
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
            print("TransferService: Transaction built successfully")
        } catch let appError as AppError {
            // Re-throw contract errors as-is so ViewController can handle them specifically
            if case .blockchain(.contract) = appError {
                throw appError
            }
            print("TransferService: ERROR building transaction: \(appError)")
            throw AppError.blockchain(.networkError("Failed to build transaction: \(appError.localizedDescription)"))
        } catch {
            print("TransferService: ERROR building transaction: \(error)")
            throw AppError.blockchain(.networkError("Failed to build transaction: \(error.localizedDescription)"))
        }

        // Step 10: Sign transaction
        progressCallback?("Signing transaction...")
        try await walletService.signTransaction(transaction)

        // Step 11: Submit transaction
        progressCallback?("Submitting transaction...")
        let txHash: String
        do {
            txHash = try await blockchainService.submitTransaction(transaction, progressCallback: progressCallback)
        } catch let appError as AppError {
            // Re-throw contract errors as-is so ViewController can handle them specifically
            if case .blockchain(.contract) = appError {
                throw appError
            }
            throw AppError.blockchain(.networkError("Failed to submit transaction: \(appError.localizedDescription)"))
        } catch {
            throw AppError.blockchain(.networkError("Failed to submit transaction: \(error.localizedDescription)"))
        }

        return TransferResult(transactionHash: txHash)
    }

    /// Parse contract ID from NDEF URL (extracts the contract ID part)
    private func parseContractIdFromNDEFUrl(_ url: String) -> String? {
        // Remove protocol if present
        var urlPath = url
        if urlPath.hasPrefix("http://") {
            urlPath = String(urlPath.dropFirst(7))
        } else if urlPath.hasPrefix("https://") {
            urlPath = String(urlPath.dropFirst(8))
        }

        // Split by '/' and expect contract ID as second component
        let components = urlPath.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count >= 2 else {
            return nil
        }

        let contractId = String(components[1])

        // Validate contract ID format
        guard contractId.count == 56 && contractId.hasPrefix("C") else {
            return nil
        }

        return contractId
    }

    // MARK: - NDEF Operations

    /// NDEF Application ID
    private let NDEF_AID: [UInt8] = [0xD2, 0x76, 0x00, 0x00, 0x85, 0x01, 0x01]

    /// NDEF File ID
    private let NDEF_FILE_ID: [UInt8] = [0xE1, 0x04]

    /// Read NDEF URL from chip using APDU commands
    private func readNDEFUrl(tag: NFCISO7816Tag, session: NFCTagReaderSession) async throws -> String? {
        print("TransferService: Reading NDEF URL...")

        do {
            // Step 1: Select NDEF Application
            guard let selectAppAPDU = NFCISO7816APDU(data: Data([0x00, 0xA4, 0x04, 0x00] + [UInt8(NDEF_AID.count)] + NDEF_AID + [0x00])) else {
                throw AppError.nfc(.readWriteFailed("Failed to create SELECT NDEF Application APDU"))
            }
            let (_, selectAppSW1, selectAppSW2) = try await tag.sendCommand(apdu: selectAppAPDU)

            guard selectAppSW1 == 0x90 && selectAppSW2 == 0x00 else {
                throw AppError.nfc(.readWriteFailed("Failed to select NDEF application: \(selectAppSW1) \(selectAppSW2)"))
            }
            print("TransferService: NDEF Application selected")

            // Step 2: Select NDEF File
            guard let selectFileAPDU = NFCISO7816APDU(data: Data([0x00, 0xA4, 0x00, 0x0C, 0x02] + NDEF_FILE_ID)) else {
                throw AppError.nfc(.readWriteFailed("Failed to create SELECT NDEF File APDU"))
            }
            let (_, selectFileSW1, selectFileSW2) = try await tag.sendCommand(apdu: selectFileAPDU)

            guard selectFileSW1 == 0x90 && selectFileSW2 == 0x00 else {
                throw AppError.nfc(.readWriteFailed("Failed to select NDEF file: \(selectFileSW1) \(selectFileSW2)"))
            }
            print("TransferService: NDEF File selected")

            // Step 3: Read NLEN (2 bytes at offset 0) to get NDEF message length
            guard let readNlenAPDU = NFCISO7816APDU(data: Data([0x00, 0xB0, 0x00, 0x00, 0x02])) else {
                throw AppError.nfc(.readWriteFailed("Failed to create READ NLEN APDU"))
            }
            let (readNlenData, readNlenSW1, readNlenSW2) = try await tag.sendCommand(apdu: readNlenAPDU)

            guard readNlenSW1 == 0x90 && readNlenSW2 == 0x00 else {
                throw AppError.nfc(.readWriteFailed("Failed to read NLEN: \(readNlenSW1) \(readNlenSW2)"))
            }

            let nlen = UInt16(readNlenData[0]) << 8 | UInt16(readNlenData[1])
            if nlen == 0 {
                print("TransferService: No NDEF data (NLEN = 0)")
                return nil
            }

            print("TransferService: NLEN = \(nlen) bytes")

            // Step 4: Read actual NDEF data (starting from offset 2)
            var ndefData = Data()
            var currentOffset: UInt16 = 2
            let maxReadLength: UInt8 = 255 - 2

            while ndefData.count < Int(nlen) {
                let bytesToRead = min(Int(nlen) - ndefData.count, Int(maxReadLength))

                guard let readBinaryAPDU = NFCISO7816APDU(data: Data([
                    0x00, 0xB0,
                    UInt8((currentOffset >> 8) & 0xFF),
                    UInt8(currentOffset & 0xFF),
                    UInt8(bytesToRead)
                ])) else {
                    throw AppError.nfc(.readWriteFailed("Failed to create READ BINARY APDU"))
                }

                let (readData, readSW1, readSW2) = try await tag.sendCommand(apdu: readBinaryAPDU)

                guard readSW1 == 0x90 && readSW2 == 0x00 else {
                    throw AppError.nfc(.readWriteFailed("Failed to read NDEF data chunk: \(readSW1) \(readSW2)"))
                }

                ndefData.append(readData)
                currentOffset += UInt16(bytesToRead)
            }

            // Parse the NDEF URL
            return parseNDEFUrl(from: ndefData)

        } catch {
            print("TransferService: Error reading NDEF: \(error)")
            throw error
        }
    }

    /// Parse NDEF URL record from raw data
    private func parseNDEFUrl(from data: Data) -> String? {
        guard data.count >= 7 else {
            print("TransferService: NDEF data too short")
            return nil
        }

        // Parse NDEF record
        let _ = data[0] // flags
        let typeLength = data[1]
        let payloadLength = data[2]
        let typeStart = 3
        let payloadStart = typeStart + Int(typeLength)

        guard data.count >= payloadStart + Int(payloadLength) else {
            print("TransferService: NDEF data truncated")
            return nil
        }

        let typeData = data.subdata(in: typeStart..<payloadStart)
        let payloadData = data.subdata(in: payloadStart..<payloadStart + Int(payloadLength))

        // Check if this is a URI record
        guard typeData.count == 1 && typeData[0] == 0x55 else { // URI record type
            print("TransferService: Not a URI record")
            return nil
        }

        // Parse URI payload
        guard payloadData.count >= 1 else {
            print("TransferService: URI payload too short")
            return nil
        }

        let uriIdentifierCode = payloadData[0]
        let uriData = payloadData.subdata(in: 1..<payloadData.count)

        // URI identifier codes (RFC 3986)
        let uriPrefixes = [
            "", // 0x00: no prefix
            "http://www.", // 0x01
            "https://www.", // 0x02
            "http://", // 0x03
            "https://", // 0x04
            "tel:", // 0x05
            "mailto:", // 0x06
            "ftp://anonymous:anonymous@", // 0x07
            "ftp://ftp.", // 0x08
            "ftps://", // 0x09
            "sftp://", // 0x0A
            "smb://", // 0x0B
            "nfs://", // 0x0C
            "ftp://", // 0x0D
            "dav://", // 0x0E
            "news:", // 0x0F
            "telnet://", // 0x10
            "imap:", // 0x11
            "rtsp://", // 0x12
            "urn:", // 0x13
            "pop:", // 0x14
            "sip:", // 0x15
            "sips:", // 0x16
            "tftp:", // 0x17
            "btspp://", // 0x18
            "btl2cap://", // 0x19
            "btgoep://", // 0x1A
            "tcpobex://", // 0x1B
            "irdaobex://", // 0x1C
            "file://", // 0x1D
            "urn:epc:id:", // 0x1E
            "urn:epc:tag:", // 0x1F
            "urn:epc:pat:", // 0x20
            "urn:epc:raw:", // 0x21
            "urn:epc:", // 0x22
            "urn:nfc:" // 0x23
        ]

        var prefix = ""
        if Int(uriIdentifierCode) < uriPrefixes.count {
            prefix = uriPrefixes[Int(uriIdentifierCode)]
        }

        guard let uriString = String(data: uriData, encoding: .utf8) else {
            print("TransferService: Failed to decode URI string")
            return nil
        }

        let fullUrl = prefix + uriString
        print("TransferService: Successfully parsed NDEF URL: \(fullUrl)")
        return fullUrl
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
                    continuation.resume(throwing: AppError.nfc(.chipError(error ?? "Unknown error")))
                }
            }
        }
    }

    /// Sign message with chip
    private func signWithChip(tag: NFCISO7816Tag, session: NFCTagReaderSession, messageHash: Data, keyIndex: UInt8) async throws -> SignatureComponents {
        guard messageHash.count == 32 else {
            throw AppError.crypto(.invalidOperation("Invalid message hash. This is an internal error. Please try again."))
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
                        continuation.resume(throwing: AppError.derSignature(.parseFailed(error.localizedDescription)))
                    }
                } else {
                    continuation.resume(throwing: AppError.nfc(.chipError(error ?? "Unknown error")))
                }
            }
        }
    }
}

