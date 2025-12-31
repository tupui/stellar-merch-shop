import Foundation
import UIKit
import CoreNFC
import stellarsdk

/// Coordinator to bridge SwiftUI to existing UIKit NFC functionality
class NFCOperationCoordinator: NSObject {
    private let walletService = WalletService()
    private let claimService = ClaimService()
    private let transferService = TransferService()
    private let mintService = MintService()
    private let blockchainService = BlockchainService()
    private let ipfsService = IPFSService()
    
    // MARK: - Constants
    private let NDEF_AID: [UInt8] = [0xD2, 0x76, 0x00, 0x00, 0x85, 0x01, 0x01]
    private let NDEF_FILE_ID: [UInt8] = [0xE1, 0x04]
    
    // Callbacks
    var onLoadNFTSuccess: ((String, UInt64) -> Void)?
    var onLoadNFTError: ((String) -> Void)?
    var onClaimSuccess: ((UInt64) -> Void)? // tokenId
    var onClaimError: ((String) -> Void)?
    var onTransferSuccess: (() -> Void)?
    var onTransferError: ((String) -> Void)?
    var onSignSuccess: ((UInt32, UInt32, String) -> Void)? // globalCounter, keyCounter, signature
    var onSignError: ((String) -> Void)?
    var onMintSuccess: ((UInt64) -> Void)? // tokenId
    var onMintError: ((String) -> Void)?
    
    // Helper to get ViewController for presenting
    private func getRootViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootViewController = window.rootViewController else {
            return nil
        }
        return rootViewController
    }
    
    // MARK: - Load NFT
    func loadNFT(completion: @escaping (Bool, String?) -> Void) {
        guard walletService.getStoredWallet() != nil else {
            completion(false, "Please login first")
            return
        }
        
        guard NFCTagReaderSession.readingAvailable else {
            completion(false, "NFC is not available on this device")
            return
        }
        
        let session = NFCTagReaderSession(pollingOption: .iso14443, delegate: self, queue: nil)
        session?.alertMessage = "Tap NFC chip to load NFT"
        session?.begin()
        
        // Store completion for later
        loadNFTCompletion = completion
    }
    
    private var loadNFTCompletion: ((Bool, String?) -> Void)?
    
    // Store NFCHelper instances to prevent deallocation
    private var claimNFCHelper: NFCHelper?
    private var transferNFCHelper: NFCHelper?
    private var mintNFCHelper: NFCHelper?
    
    // MARK: - Claim NFT
    func claimNFT(completion: @escaping (Bool, String?) -> Void) {
        guard walletService.getStoredWallet() != nil else {
            completion(false, "Please login first")
            return
        }
        
        guard !AppConfig.shared.contractId.isEmpty else {
            completion(false, "Please set the contract ID in Settings")
            return
        }
        
        guard NFCTagReaderSession.readingAvailable else {
            completion(false, "NFC is not available on this device")
            return
        }
        
        // Store helper as property to prevent deallocation
        claimNFCHelper = NFCHelper()
        claimNFCHelper?.OnTagEvent = { [weak self] success, tag, session, error in
            guard let self = self else { return }
            if success, let tag = tag, let session = session {
                // Show loading state immediately
                Task { @MainActor in
                    session.alertMessage = "Processing claim... Please wait."
                }
                
                // Run blockchain operations on background thread
                Task.detached {
                    do {
                        let claimResult = try await self.claimService.executeClaim(
                            tag: tag,
                            session: session,
                            keyIndex: 0x01
                        ) { progress in
                            Task { @MainActor in
                                session.alertMessage = progress
                            }
                        }
                        
                        // Success - update UI on main thread
                        await MainActor.run {
                            session.alertMessage = "Claim successful!"
                            completion(true, nil)
                            // Trigger callback with tokenId for NFT loading
                            self.onClaimSuccess?(claimResult.tokenId)
                        }
                        
                        // Wait for confetti animation, then invalidate session
                        try await Task.sleep(nanoseconds: 3_000_000_000)
                        
                        await MainActor.run {
                            session.invalidate()
                            self.claimNFCHelper = nil
                        }
                    } catch {
                        // Error - update UI on main thread
                        await MainActor.run {
                            let errorMessage = (error as? AppError)?.localizedDescription ?? "Claim failed"
                            session.invalidate(errorMessage: errorMessage)
                            completion(false, errorMessage)
                            self.onClaimError?(errorMessage)
                            self.claimNFCHelper = nil
                        }
                    }
                }
            } else {
                let errorMsg = error ?? "Failed to detect NFC tag"
                completion(false, errorMsg)
                self.onClaimError?(errorMsg)
                self.claimNFCHelper = nil
            }
        }
        claimNFCHelper?.BeginSession()
    }
    
    // MARK: - Transfer NFT
    func transferNFT(recipientAddress: String, tokenId: UInt64, completion: @escaping (Bool, String?) -> Void) {
        guard walletService.getStoredWallet() != nil else {
            completion(false, "Please login first")
            return
        }
        
        guard !AppConfig.shared.contractId.isEmpty else {
            completion(false, "Please set the contract ID in Settings")
            return
        }
        
        guard NFCTagReaderSession.readingAvailable else {
            completion(false, "NFC is not available on this device")
            return
        }
        
        // Store helper as property to prevent deallocation
        transferNFCHelper = NFCHelper()
        transferNFCHelper?.OnTagEvent = { [weak self] success, tag, session, error in
            guard let self = self else { return }
            if success, let tag = tag, let session = session {
                // Show loading state immediately
                Task { @MainActor in
                    session.alertMessage = "Processing transfer... Please wait."
                }
                
                // Run blockchain operations on background thread
                Task.detached {
                    do {
                        _ = try await self.transferService.executeTransfer(
                            tag: tag,
                            session: session,
                            keyIndex: 0x01,
                            recipientAddress: recipientAddress,
                            tokenId: tokenId
                        ) { progress in
                            Task { @MainActor in
                                session.alertMessage = progress
                            }
                        }
                        
                        // Success - update UI on main thread
                        await MainActor.run {
                            session.alertMessage = "Transfer successful!"
                            session.invalidate()
                            completion(true, nil)
                            self.onTransferSuccess?()
                            self.transferNFCHelper = nil
                        }
                    } catch {
                        // Error - update UI on main thread
                        await MainActor.run {
                            let errorMessage = (error as? AppError)?.localizedDescription ?? "Transfer failed"
                            session.invalidate(errorMessage: errorMessage)
                            completion(false, errorMessage)
                            self.onTransferError?(errorMessage)
                            self.transferNFCHelper = nil
                        }
                    }
                }
            } else {
                let errorMsg = error ?? "Failed to detect NFC tag"
                completion(false, errorMsg)
                self.onTransferError?(errorMsg)
                self.transferNFCHelper = nil
            }
        }
        transferNFCHelper?.BeginSession()
    }
    
    // MARK: - Sign Message
    func signMessage(message: Data, completion: @escaping (Bool, UInt32?, UInt32?, String?) -> Void) {
        guard NFCTagReaderSession.readingAvailable else {
            completion(false, nil, nil, "NFC is not available on this device")
            return
        }
        
        let session = NFCTagReaderSession(pollingOption: .iso14443, delegate: self, queue: nil)
        session?.alertMessage = "Tap NFC chip to sign message"
        session?.begin()
        
        // Store message and completion
        signMessageData = message
        signMessageCompletion = completion
    }
    
    private var signMessageData: Data?
    private var signMessageCompletion: ((Bool, UInt32?, UInt32?, String?) -> Void)?
    
    // MARK: - Mint NFT
    func mintNFT(completion: @escaping (Bool, String?) -> Void) {
        guard walletService.getStoredWallet() != nil else {
            completion(false, "Please login first")
            return
        }
        
        guard !AppConfig.shared.contractId.isEmpty else {
            completion(false, "Please set the contract ID in Settings")
            return
        }
        
        guard AppConfig.shared.isAdminMode else {
            completion(false, "Admin mode required for minting")
            return
        }
        
        guard NFCTagReaderSession.readingAvailable else {
            completion(false, "NFC is not available on this device")
            return
        }
        
        // Store helper as property to prevent deallocation
        mintNFCHelper = NFCHelper()
        mintNFCHelper?.OnTagEvent = { [weak self] success, tag, session, error in
            guard let self = self else { return }
            if success, let tag = tag, let session = session {
                // Show loading state immediately
                Task { @MainActor in
                    session.alertMessage = "Processing mint... Please wait."
                }
                
                // Run blockchain operations on background thread
                Task.detached {
                    do {
                        let mintResult = try await self.mintService.executeMint(
                            tag: tag,
                            session: session,
                            keyIndex: 0x01
                        ) { progress in
                            Task { @MainActor in
                                session.alertMessage = progress
                            }
                        }
                        
                        // Success - update UI on main thread
                        await MainActor.run {
                            session.alertMessage = "Mint successful!"
                            completion(true, nil)
                            // Trigger callback with tokenId
                            self.onMintSuccess?(mintResult.tokenId)
                        }
                        
                        // Wait for confetti animation, then invalidate session
                        try await Task.sleep(nanoseconds: 3_000_000_000)
                        
                        await MainActor.run {
                            session.invalidate()
                            self.mintNFCHelper = nil
                        }
                    } catch {
                        // Error - update UI on main thread
                        await MainActor.run {
                            let errorMessage = (error as? AppError)?.localizedDescription ?? "Mint failed"
                            session.invalidate(errorMessage: errorMessage)
                            completion(false, errorMessage)
                            self.onMintError?(errorMessage)
                            self.mintNFCHelper = nil
                        }
                    }
                }
            } else {
                let errorMsg = error ?? "Failed to detect NFC tag"
                completion(false, errorMsg)
                self.onMintError?(errorMsg)
                self.mintNFCHelper = nil
            }
        }
        mintNFCHelper?.BeginSession()
    }
    
    /// Reset all NFC helper state - call this if operations get stuck
    func resetState() {
        claimNFCHelper = nil
        transferNFCHelper = nil
        mintNFCHelper = nil
        loadNFTCompletion = nil
        signMessageData = nil
        signMessageCompletion = nil
    }
}

// MARK: - NFCTagReaderSessionDelegate
extension NFCOperationCoordinator: NFCTagReaderSessionDelegate {
    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        print("NFCOperationCoordinator: Session became active")
    }
    
    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        print("NFCOperationCoordinator: Session invalidated with error: \(error)")
        
        if let nfcError = error as? NFCReaderError {
            switch nfcError.code {
            case .readerSessionInvalidationErrorUserCanceled:
                // User canceled, notify completion
                if let completion = loadNFTCompletion {
                    completion(false, "User canceled")
                    onLoadNFTError?("User canceled")
                    loadNFTCompletion = nil
                }
                if let completion = signMessageCompletion {
                    completion(false, nil, nil, "User canceled")
                    onSignError?("User canceled")
                    signMessageCompletion = nil
                    signMessageData = nil
                }
                return
            default:
                break
            }
        }
        
        // Handle other errors
        if let completion = loadNFTCompletion {
            let errorMsg = error.localizedDescription
            completion(false, errorMsg)
            onLoadNFTError?(errorMsg)
            loadNFTCompletion = nil
        }
        if let completion = signMessageCompletion {
            let errorMsg = error.localizedDescription
            completion(false, nil, nil, errorMsg)
            onSignError?(errorMsg)
            signMessageCompletion = nil
            signMessageData = nil
        }
    }
    
    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        print("NFCOperationCoordinator: Detected \(tags.count) tags")
        
        guard let firstTag = tags.first else {
            session.invalidate(errorMessage: "No NFC tag found")
            return
        }
        
        // Handle load NFT
        if loadNFTCompletion != nil {
            Task {
                await handleLoadNFTTag(tag: firstTag, session: session)
            }
            return
        }
        
        // Handle sign message
        if signMessageCompletion != nil, let messageData = signMessageData {
            Task {
                await handleSignMessageTag(tag: firstTag, session: session, messageData: messageData)
            }
            return
        }
    }
    
    // MARK: - Load NFT Handler
    private func handleLoadNFTTag(tag: NFCTag, session: NFCTagReaderSession) async {
        guard case .iso7816(let iso7816Tag) = tag else {
            await MainActor.run {
                let errorMsg = "Invalid tag type"
                session.invalidate(errorMessage: errorMsg)
                loadNFTCompletion?(false, errorMsg)
                onLoadNFTError?(errorMsg)
                loadNFTCompletion = nil
            }
            return
        }
        
        session.connect(to: tag) { error in
            if let error = error {
                print("NFCOperationCoordinator: Failed to connect to tag: \(error)")
                session.invalidate(errorMessage: "Failed to connect to NFC tag")
            }
        }
        
        do {
            // Read NDEF to get contract ID
            let ndefUrl = try await readNDEFUrl(tag: iso7816Tag, session: session)
            guard let ndefUrl = ndefUrl else {
                throw AppError.nfc(.readWriteFailed("No NDEF URL found"))
            }
            
            guard let contractId = parseContractIdFromNDEFUrl(ndefUrl) else {
                throw AppError.validation("Invalid contract ID in NFC tag")
            }
            
            // Read chip public key
            let chipPublicKey = try await readChipPublicKey(tag: iso7816Tag, session: session, keyIndex: 0x01)
            guard let publicKeyData = Data(hexString: chipPublicKey) else {
                throw AppError.crypto(.invalidKey("Invalid public key format from chip"))
            }
            
            // Update session message before blockchain operation
            await MainActor.run {
                session.alertMessage = "Getting token ID from blockchain..."
            }
            
            // Get token ID (this needs to happen while session is active for proper flow)
            let tokenId = try await getTokenIdForChip(contractId: contractId, publicKey: publicKeyData)
            
            // Close NFC session immediately after getting token ID
            await MainActor.run {
                session.alertMessage = "Chip data read successfully"
                session.invalidate()
            }
            
            // Continue on background thread to load NFT
            await MainActor.run {
                loadNFTCompletion?(true, nil)
                loadNFTCompletion = nil
                // Trigger NFT view presentation
                onLoadNFTSuccess?(contractId, tokenId)
            }
        } catch {
            await MainActor.run {
                let errorMessage = (error as? AppError)?.localizedDescription ?? "Failed to load NFT"
                session.invalidate(errorMessage: errorMessage)
                loadNFTCompletion?(false, errorMessage)
                onLoadNFTError?(errorMessage)
                loadNFTCompletion = nil
            }
        }
    }
    
    // MARK: - Sign Message Handler
    private func handleSignMessageTag(tag: NFCTag, session: NFCTagReaderSession, messageData: Data) async {
        guard case .iso7816(let iso7816Tag) = tag else {
            await MainActor.run {
                session.invalidate(errorMessage: "Invalid tag type")
                signMessageCompletion?(false, nil, nil, "Invalid tag type")
                signMessageCompletion = nil
            }
            return
        }
        
        session.connect(to: tag) { error in
            if let error = error {
                print("NFCOperationCoordinator: Failed to connect to tag: \(error)")
                session.invalidate(errorMessage: "Failed to connect to NFC tag")
            }
        }
        
        let commandHandler = BlockchainCommandHandler(tag_iso7816: iso7816Tag, reader_session: session)
        commandHandler.ActionGenerateSignature(key_index: 0x01, message_digest: messageData) { [weak self] success, response, error, session in
            guard let self = self else { return }
            
            if success, let response = response, response.count >= 8 {
                let globalCounterData = response.subdata(in: 0..<4)
                let keyCounterData = response.subdata(in: 4..<8)
                let derSignature = response.subdata(in: 8..<response.count)
                
                // Convert 4-byte Data to UInt32 (big-endian)
                let globalCounter = globalCounterData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
                let keyCounter = keyCounterData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
                let derSignatureHex = derSignature.hexEncodedString()
                
                DispatchQueue.main.async {
                    session.alertMessage = "Signature generated successfully"
                    session.invalidate()
                    self.signMessageCompletion?(true, globalCounter, keyCounter, derSignatureHex)
                    // Trigger callback
                    self.onSignSuccess?(globalCounter, keyCounter, derSignatureHex)
                    self.signMessageCompletion = nil
                    self.signMessageData = nil
                }
            } else {
                DispatchQueue.main.async {
                    let errorMsg = error ?? "Failed to generate signature"
                    session.invalidate(errorMessage: errorMsg)
                    self.signMessageCompletion?(false, nil, nil, errorMsg)
                    self.onSignError?(errorMsg)
                    self.signMessageCompletion = nil
                    self.signMessageData = nil
                }
            }
        }
    }
    
    // MARK: - Helper Methods (copied from ViewController)
    private func readNDEFUrl(tag: NFCISO7816Tag, session: NFCTagReaderSession) async throws -> String? {
        // Select NDEF Application
        guard let selectAppAPDU = NFCISO7816APDU(data: Data([0x00, 0xA4, 0x04, 0x00] + [UInt8(NDEF_AID.count)] + NDEF_AID + [0x00])) else {
            return nil
        }
        let (_, selectAppSW1, selectAppSW2) = try await tag.sendCommand(apdu: selectAppAPDU)
        guard selectAppSW1 == 0x90 && selectAppSW2 == 0x00 else { return nil }
        
        // Select NDEF File
        guard let selectFileAPDU = NFCISO7816APDU(data: Data([0x00, 0xA4, 0x00, 0x0C, 0x02] + NDEF_FILE_ID)) else {
            return nil
        }
        let (_, selectFileSW1, selectFileSW2) = try await tag.sendCommand(apdu: selectFileAPDU)
        guard selectFileSW1 == 0x90 && selectFileSW2 == 0x00 else { return nil }
        
        // Read NLEN
        guard let readNlenAPDU = NFCISO7816APDU(data: Data([0x00, 0xB0, 0x00, 0x00, 0x02])) else {
            return nil
        }
        let (readNlenData, readNlenSW1, readNlenSW2) = try await tag.sendCommand(apdu: readNlenAPDU)
        guard readNlenSW1 == 0x90 && readNlenSW2 == 0x00 else { return nil }
        
        let nlen = UInt16(readNlenData[0]) << 8 | UInt16(readNlenData[1])
        if nlen == 0 { return nil }
        
        // Read NDEF data
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
            ])) else { return nil }
            
            let (readData, readSW1, readSW2) = try await tag.sendCommand(apdu: readBinaryAPDU)
            guard readSW1 == 0x90 && readSW2 == 0x00 else { return nil }
            
            ndefData.append(readData)
            currentOffset += UInt16(bytesToRead)
        }
        
        return parseNDEFUrl(from: ndefData)
    }
    
    private func parseNDEFUrl(from data: Data) -> String? {
        guard data.count >= 7 else { return nil }
        
        let _ = data[0] // flags
        let typeLength = data[1]
        let payloadLength = data[2]
        let typeStart = 3
        let payloadStart = typeStart + Int(typeLength)
        
        guard data.count >= payloadStart + Int(payloadLength) else { return nil }
        
        let typeData = data.subdata(in: typeStart..<payloadStart)
        let payloadData = data.subdata(in: payloadStart..<payloadStart + Int(payloadLength))
        
        guard typeData.count == 1 && typeData[0] == 0x55 else { return nil }
        guard payloadData.count >= 1 else { return nil }
        
        let uriIdentifierCode = payloadData[0]
        let uriData = payloadData.subdata(in: 1..<payloadData.count)
        
        let uriPrefixes = [
            "", "http://www.", "https://www.", "http://", "https://",
            "tel:", "mailto:", "ftp://anonymous:anonymous@", "ftp://ftp.",
            "ftps://", "sftp://", "smb://", "nfs://", "ftp://", "dav://",
            "news:", "telnet://", "imap:", "rtsp://", "urn:", "pop:",
            "sip:", "sips:", "tftp:", "btspp://", "btl2cap://", "btgoep://",
            "tcpobex://", "irdaobex://", "file://", "urn:epc:id:", "urn:epc:tag:",
            "urn:epc:pat:", "urn:epc:raw:", "urn:epc:", "urn:nfc:"
        ]
        
        var prefix = ""
        if Int(uriIdentifierCode) < uriPrefixes.count {
            prefix = uriPrefixes[Int(uriIdentifierCode)]
        }
        
        guard let uriString = String(data: uriData, encoding: .utf8) else { return nil }
        return prefix + uriString
    }
    
    private func parseContractIdFromNDEFUrl(_ url: String) -> String? {
        var urlPath = url
        if urlPath.hasPrefix("http://") {
            urlPath = String(urlPath.dropFirst(7))
        } else if urlPath.hasPrefix("https://") {
            urlPath = String(urlPath.dropFirst(8))
        }
        
        let components = urlPath.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count >= 2 else { return nil }
        
        let contractId = String(components[1])
        guard contractId.count == 56 && contractId.hasPrefix("C") else { return nil }
        return contractId
    }
    
    private func readChipPublicKey(tag: NFCISO7816Tag, session: NFCTagReaderSession, keyIndex: UInt8) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let commandHandler = BlockchainCommandHandler(tag_iso7816: tag, reader_session: session)
            commandHandler.ActionGetKey(key_index: keyIndex) { success, response, error, session in
                if success, let response = response, response.count >= 73 {
                    let publicKeyData = response.subdata(in: 9..<73)
                    var fullPublicKey = Data([0x04])
                    fullPublicKey.append(publicKeyData)
                    let publicKeyHex = fullPublicKey.map { String(format: "%02x", $0) }.joined()
                    continuation.resume(returning: publicKeyHex)
                } else {
                    continuation.resume(throwing: AppError.nfc(.chipError(error ?? "Failed to read chip public key")))
                }
            }
        }
    }
    
    private func getTokenIdForChip(contractId: String, publicKey: Data) async throws -> UInt64 {
        guard walletService.getStoredWallet() != nil,
              let privateKey = try SecureKeyStorage().loadPrivateKey() else {
            throw AppError.wallet(.noWallet)
        }
        
        let keyPair = try KeyPair(secretSeed: privateKey)
        return try await blockchainService.getTokenId(contractId: contractId, publicKey: publicKey, sourceKeyPair: keyPair)
    }
}

