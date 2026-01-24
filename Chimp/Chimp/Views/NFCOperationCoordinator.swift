import Foundation
import UIKit
import CoreNFC
import stellarsdk
import OSLog

/// Coordinator to bridge SwiftUI to existing UIKit NFC functionality
class NFCOperationCoordinator: NSObject {
    private let walletService = WalletService.shared
    private let nftService = NFTService()
    private let blockchainService = BlockchainService()
    
    // Callbacks
    var onLoadNFTSuccess: ((String, UInt64) -> Void)?
    var onLoadNFTError: ((String) -> Void)?
    var onClaimSuccess: ((UInt64, String) -> Void)? // tokenId, contractId
    var onClaimError: ((String) -> Void)?
    var onTransferSuccess: (() -> Void)?
    var onTransferError: ((String) -> Void)?
    var onSignSuccess: ((UInt32, UInt32, String) -> Void)? // globalCounter, keyCounter, signature
    var onSignError: ((String) -> Void)?
    var onMintSuccess: ((UInt64) -> Void)? // tokenId
    var onMintError: ((String) -> Void)?
    
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
        
        // Store helper as property to prevent deallocation
        loadNFTNFCHelper = NFCHelper()
        loadNFTNFCHelper?.OnTagEvent = { [weak self] success, tag, session, error in
            guard let self = self else { return }
            if success, let tag = tag, let session = session {
                Task { @MainActor in
                    session.alertMessage = "Reading chip information..."
                }
                
                Task.detached {
                    do {
                        // Read NDEF to get contract ID
                        let ndefUrl = try await NDEFReader.readNDEFUrl(tag: tag, session: session)
                        guard let ndefUrl = ndefUrl else {
                            throw AppError.nfc(.readWriteFailed("No NDEF URL found"))
                        }
                        
                        guard let contractId = NDEFReader.parseContractIdFromNDEFUrl(ndefUrl) else {
                            throw AppError.validation("Invalid contract ID in NFC tag")
                        }
                        
                        // Read chip public key
                        let chipPublicKey = try await ChipOperations.readChipPublicKey(tag: tag, session: session, keyIndex: 0x01)
                        guard let publicKeyData = Data(hexString: chipPublicKey) else {
                            throw AppError.crypto(.invalidKey("Invalid public key format from chip"))
                        }
                        
                        // Update session message before blockchain operation
                        await MainActor.run {
                            session.alertMessage = "Reading chip information..."
                        }
                        
                        // Get token ID (this needs to happen while session is active for proper flow)
                        let tokenId = try await self.getTokenIdForChip(contractId: contractId, publicKey: publicKeyData)
                        
                        // Close NFC session immediately after getting token ID
                        await MainActor.run {
                            session.alertMessage = "Chip information read successfully"
                            session.invalidate()
                            completion(true, nil)
                            self.onLoadNFTSuccess?(contractId, tokenId)
                            self.loadNFTNFCHelper = nil
                        }
                    } catch {
                        await MainActor.run {
                            let errorMessage = (error as? AppError)?.localizedDescription ?? "Failed to load NFT"
                            session.invalidate(errorMessage: errorMessage)
                            completion(false, errorMessage)
                            self.onLoadNFTError?(errorMessage)
                            self.loadNFTNFCHelper = nil
                        }
                    }
                }
            } else {
                let errorMsg = error ?? "Failed to detect NFC tag"
                completion(false, errorMsg)
                self.onLoadNFTError?(errorMsg)
                self.loadNFTNFCHelper = nil
            }
        }
        loadNFTNFCHelper?.BeginSession()
    }
    
    // Store NFCHelper instances to prevent deallocation
    private var claimNFCHelper: NFCHelper?
    private var transferNFCHelper: NFCHelper?
    private var transferReadNFCHelper: NFCHelper?
    private var mintNFCHelper: NFCHelper?
    private var loadNFTNFCHelper: NFCHelper?
    private var signMessageNFCHelper: NFCHelper?
    
    // MARK: - Claim NFT
    func claimNFT(completion: @escaping (Bool, String?) -> Void) {
        guard walletService.getStoredWallet() != nil else {
            completion(false, "Please login first")
            return
        }
        
        // Contract ID is read from chip NDEF, not from Settings
        
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
                    session.alertMessage = "Preparing to claim NFT..."
                }
                
                // Run blockchain operations on background thread
                Task.detached {
                    do {
                        let claimResult = try await self.nftService.executeClaim(
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
                            session.alertMessage = "NFT claimed successfully!"
                            session.invalidate()
                            completion(true, nil)
                            // Trigger callback with tokenId for NFT loading
                            self.onClaimSuccess?(claimResult.tokenId, claimResult.contractId)
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
    
    // MARK: - Read NFT for Transfer (first scan to get token ID)
    func readNFTForTransfer(completion: @escaping (Bool, UInt64?, String?) -> Void) {
        guard walletService.getStoredWallet() != nil else {
            completion(false, nil, "Please login first")
            return
        }
        
        guard NFCTagReaderSession.readingAvailable else {
            completion(false, nil, "NFC is not available on this device")
            return
        }
        
        // Store helper as property to prevent deallocation
        transferReadNFCHelper = NFCHelper()
        transferReadNFCHelper?.OnTagEvent = { [weak self] success, tag, session, error in
            guard let self = self else { return }
            if success, let tag = tag, let session = session {
                Task { @MainActor in
                    session.alertMessage = "Reading chip information..."
                }
                
                Task.detached {
                    do {
                        // Read NDEF to get contract ID and token ID
                        let ndefUrl = try await NDEFReader.readNDEFUrl(tag: tag, session: session)
                        guard let ndefUrl = ndefUrl else {
                            throw AppError.validation("No NDEF data found on chip")
                        }
                        
                        let tokenId = NDEFReader.parseTokenIdFromNDEFUrl(ndefUrl)
                        guard let tokenId = tokenId else {
                            throw AppError.validation("Token ID not found on chip. This NFT may not be claimed yet.")
                        }
                        
                        await MainActor.run {
                            session.alertMessage = "Chip read successfully!"
                            session.invalidate()
                            completion(true, tokenId, nil)
                            self.transferReadNFCHelper = nil
                        }
                    } catch let error as AppError {
                        await MainActor.run {
                            session.alertMessage = error.localizedDescription
                            session.invalidate(errorMessage: error.localizedDescription)
                            completion(false, nil, error.localizedDescription)
                            self.transferReadNFCHelper = nil
                        }
                    } catch {
                        let message = (error as? AppError)?.localizedDescription ?? "Failed to read chip. Please try again."
                        await MainActor.run {
                            session.alertMessage = message
                            session.invalidate(errorMessage: message)
                            completion(false, nil, message)
                            self.transferReadNFCHelper = nil
                        }
                    }
                }
            } else if let error = error {
                completion(false, nil, error)
                self.transferReadNFCHelper = nil
            }
        }
        
        transferReadNFCHelper?.BeginSession()
    }
    
    // MARK: - Transfer NFT (second scan to complete transfer)
    func transferNFT(recipientAddress: String, tokenId: UInt64, completion: @escaping (Bool, String?) -> Void) {
        guard walletService.getStoredWallet() != nil else {
            completion(false, "Please login first")
            return
        }
        
        // Contract ID is read from chip NDEF, not from Settings
        
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
                    session.alertMessage = "Preparing to transfer NFT..."
                }
                
                // Run blockchain operations on background thread
                Task.detached {
                    do {
                        _ = try await self.nftService.executeTransfer(
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
                            session.alertMessage = "NFT transferred successfully!"
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
        
        // Store helper as property to prevent deallocation
        signMessageNFCHelper = NFCHelper()
        signMessageNFCHelper?.OnTagEvent = { [weak self] success, tag, session, error in
            guard let self = self else { return }
            if success, let tag = tag, let session = session {
                Task { @MainActor in
                    session.alertMessage = "Signing message..."
                }
                
                let commandHandler = BlockchainCommandHandler(tag_iso7816: tag, readerSession: session)
                commandHandler.generateSignature(keyIndex: 0x01, messageDigest: message) { [weak self] success, response, error, session in
                    guard let self = self else { return }
                    
                    if success, let response = response, response.count >= 8 {
                        let globalCounterData = response.subdata(in: 0..<4)
                        let keyCounterData = response.subdata(in: 4..<8)
                        let derSignature = response.subdata(in: 8..<response.count)
                        
                        // Convert 4-byte Data to UInt32 (big-endian) with bounds checking
                        guard globalCounterData.count == 4, keyCounterData.count == 4 else {
                            DispatchQueue.main.async {
                                let errorMsg = "Invalid counter data length"
                                session.invalidate(errorMessage: errorMsg)
                                completion(false, nil, nil, errorMsg)
                                self.onSignError?(errorMsg)
                                self.signMessageNFCHelper = nil
                            }
                            return
                        }
                        
                        let globalCounter = globalCounterData.withUnsafeBytes { buffer -> UInt32 in
                            guard buffer.count >= MemoryLayout<UInt32>.size else {
                                return 0
                            }
                            return buffer.load(as: UInt32.self).bigEndian
                        }
                        let keyCounter = keyCounterData.withUnsafeBytes { buffer -> UInt32 in
                            guard buffer.count >= MemoryLayout<UInt32>.size else {
                                return 0
                            }
                            return buffer.load(as: UInt32.self).bigEndian
                        }
                        let derSignatureHex = derSignature.hexEncodedString()
                        
                        DispatchQueue.main.async {
                            session.alertMessage = "Message signed successfully"
                            session.invalidate()
                            completion(true, globalCounter, keyCounter, derSignatureHex)
                            self.onSignSuccess?(globalCounter, keyCounter, derSignatureHex)
                            self.signMessageNFCHelper = nil
                        }
                    } else {
                        DispatchQueue.main.async {
                            let errorMsg = error ?? "Failed to generate signature"
                            session.invalidate(errorMessage: errorMsg)
                            completion(false, nil, nil, errorMsg)
                            self.onSignError?(errorMsg)
                            self.signMessageNFCHelper = nil
                        }
                    }
                }
            } else {
                let errorMsg = error ?? "Failed to detect NFC tag"
                completion(false, nil, nil, errorMsg)
                self.onSignError?(errorMsg)
                self.signMessageNFCHelper = nil
            }
        }
        signMessageNFCHelper?.BeginSession()
    }
    
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
                    session.alertMessage = "Preparing to mint NFT..."
                }
                
                // Run blockchain operations on background thread
                Task.detached {
                    do {
                        let mintResult = try await self.nftService.executeMint(
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
                            session.alertMessage = "NFT minted successfully!"
                            session.invalidate()
                            completion(true, nil)
                            // Trigger callback with tokenId
                            self.onMintSuccess?(mintResult.tokenId)
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
        transferReadNFCHelper = nil
        mintNFCHelper = nil
        loadNFTNFCHelper = nil
        signMessageNFCHelper = nil
    }
    
    private func readChipPublicKey(tag: NFCISO7816Tag, session: NFCTagReaderSession, keyIndex: UInt8) async throws -> String {
        return try await ChipOperations.readChipPublicKey(tag: tag, session: session, keyIndex: keyIndex)
    }
    
    private func getTokenIdForChip(contractId: String, publicKey: Data) async throws -> UInt64 {
        guard let wallet = walletService.getStoredWallet() else {
            throw AppError.wallet(.noWallet)
        }
        
        // Use public address only - no private key needed for read-only queries
        return try await blockchainService.getTokenId(
            contractId: contractId,
            publicKey: publicKey,
            accountId: wallet.address
        )
    }
}

