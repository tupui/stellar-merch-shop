/**
 * NFC Service
 * Manages NFCISO7816TagReaderSession and APDU communication with SECORA chip
 */

import Foundation
import CoreNFC
import UIKit

class NFCService {
    weak var delegate: NFCServiceDelegate?
    
    private var session: NFCTagReaderSession?
    // CRITICAL: Keep strong reference to delegate to prevent deallocation
    // NFCTagReaderSession only holds a weak reference, so delegate can be deallocated
    // if we don't keep a strong reference here
    private var sessionDelegate: NFCSessionDelegate?
    var currentTag: NFCISO7816Tag?
    
    // Completion handlers for operations
    private var readPublicKeyCompletion: ((Result<String, Error>) -> Void)?
    private var signMessageCompletion: ((Result<(r: String, s: String, recoveryId: Int), Error>) -> Void)?
    private var signMessageHash: Data?
    
    /**
     * Start NFC session
     * Uses NFCTagReaderSession with ISO 14443 polling for ISO 7816 tags (SECORA chips)
     * MUST be called on main thread
     */
    func startSession() {
        print("🔵 NFC: startSession() called on thread: \(Thread.isMainThread ? "main" : "background")")
        
        // Log device and iOS version information for diagnostics
        let device = UIDevice.current
        print("🔵 NFC: Device: \(device.model) (\(device.name))")
        print("🔵 NFC: iOS Version: \(device.systemName) \(device.systemVersion)")
        print("🔵 NFC: Device identifier: \(device.identifierForVendor?.uuidString ?? "unknown")")
        
        // Ensure we're on the main thread
        if !Thread.isMainThread {
            print("🔵 NFC: Not on main thread, dispatching to main...")
            DispatchQueue.main.async { [weak self] in
                self?.startSession()
            }
            return
        }
        
        // Check if running on simulator
        #if targetEnvironment(simulator)
        print("🔴 NFC: Running on simulator - NFC not available")
        let error = NSError(domain: "NFCService", code: -1, userInfo: [NSLocalizedDescriptionKey: "NFC is not available on iOS Simulator. Please run on a physical device."])
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.nfcService(self, didFailWithError: error)
        }
        return
        #endif
        
        print("🔵 NFC: Checking NFCTagReaderSession.readingAvailable...")
        guard NFCTagReaderSession.readingAvailable else {
            print("🔴 NFC: NFCTagReaderSession.readingAvailable = false")
            let errorMessage = "NFC not available on this device. " +
                "Possible causes:\n" +
                "1. NFC is disabled in Settings\n" +
                "2. Device doesn't support NFC\n" +
                "3. App doesn't have NFC capability enabled\n" +
                "4. Entitlements file not properly configured\n" +
                "5. NFC Tag Reading requires a paid Apple Developer account (personal teams don't support this capability)"
            
            let error = NSError(domain: "NFCService", code: -1, userInfo: [NSLocalizedDescriptionKey: errorMessage])
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.nfcService(self, didFailWithError: error)
            }
            return
        }
        print("✅ NFC: NFCTagReaderSession.readingAvailable = true")
        
        // Don't start a new session if one is already active
        if session != nil {
            print("⚠️ NFC: Session already exists, not starting new one")
            return
        }
        
        print("🔵 NFC: Creating NFCSessionDelegate...")
        // Use NFCTagReaderSession with ISO 14443 polling for ISO 7816 tags
        // CRITICAL: Keep strong reference to delegate to prevent deallocation
        // The session only holds a weak reference, so we must retain it
        sessionDelegate = NFCSessionDelegate(service: self)
        print("✅ NFC: NFCSessionDelegate created: \(sessionDelegate != nil ? "success" : "failed")")
        print("🔵 NFC: Delegate retain count check - delegate exists: \(sessionDelegate != nil)")
        
        print("🔵 NFC: Creating NFCTagReaderSession with pollingOption: [.iso14443]")
        // Per Infineon example: use nil for queue to get default queue
        // This ensures delegate methods are called on the correct queue
        guard let delegate = sessionDelegate else {
            print("🔴 NFC: Delegate is nil, cannot create session")
            let error = NSError(domain: "NFCService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create delegate"])
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.nfcService(self, didFailWithError: error)
            }
            return
        }
        
        // SECORA uses ISO 14443 (ISO 7816). Keep polling focused on iso14443.
        print("🔵 NFC: Using polling option: .iso14443")
        
        session = NFCTagReaderSession(
            pollingOption: [.iso14443],
            delegate: delegate,
            queue: nil  // Use nil to get default queue (per Infineon example - delegate handles thread safety)
        )
        
        guard let session = session else {
            print("🔴 NFC: Failed to create NFCTagReaderSession")
            let error = NSError(domain: "NFCService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create NFC session"])
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.nfcService(self, didFailWithError: error)
            }
            return
        }
        print("✅ NFC: NFCTagReaderSession created successfully")
        print("🔵 NFC: Session object: \(session)")
        print("🔵 NFC: Session delegate: \(session.delegate != nil ? "exists" : "nil")")
        
        print("🔵 NFC: Calling session.begin()...")
        // Begin the session - this will show the NFC scan UI
        // Alert message will be set in tagReaderSessionDidBecomeActive for better iOS compatibility
        session.begin()
        print("✅ NFC: session.begin() called")
        print("🔵 NFC: After begin() - session delegate: \(session.delegate != nil ? "exists" : "nil")")
        
        // Add a timeout check - if didDetect isn't called within 30 seconds, log a warning
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self = self, let session = self.session else { return }
            print("⚠️ NFC: 30 seconds elapsed - didDetect still not called")
            print("⚠️ NFC: Session state - delegate exists: \(session.delegate != nil)")
            print("⚠️ NFC: This might indicate:")
            print("   1. Chip not being detected (hardware issue)")
            print("   2. select-identifiers in Info.plist filtering out the tag")
            print("   3. Polling option mismatch")
        }
    }
    
    /**
     * Stop NFC session
     */
    func stopSession() {
        print("🔵 NFC: stopSession() called")
        if let session = session {
            print("🔵 NFC: Invalidating session...")
            session.invalidate()
        }
        session = nil
        sessionDelegate = nil
        currentTag = nil
        readPublicKeyCompletion = nil
        signMessageCompletion = nil
        signMessageHash = nil
        print("✅ NFC: Session stopped and cleaned up")
    }
    
    /**
     * Session was invalidated
     */
    func sessionInvalidated(error: Error) {
        currentTag = nil
        session = nil
        sessionDelegate = nil
        
        // Fail any pending operations
        if let completion = readPublicKeyCompletion {
            readPublicKeyCompletion = nil
            completion(.failure(error))
        }
        if let completion = signMessageCompletion {
            signMessageCompletion = nil
            signMessageHash = nil
            completion(.failure(error))
        }
        
        // Only report errors (not user cancellation)
        if let nfcError = error as? NFCReaderError {
            if nfcError.code != .readerSessionInvalidationErrorUserCanceled {
                delegate?.nfcService(self, didFailWithError: error)
            }
        } else {
            delegate?.nfcService(self, didFailWithError: error)
        }
    }
    
    /**
     * Called by delegate when tag is connected - proceed with pending operation
     */
    func onTagConnected() {
        print("🔵 NFC: onTagConnected() called")
        if readPublicKeyCompletion != nil {
            print("🔵 NFC: Proceeding with readPublicKeyAfterConnection()")
            readPublicKeyAfterConnection()
        } else if signMessageCompletion != nil {
            print("🔵 NFC: Proceeding with signMessageAfterConnection()")
            signMessageAfterConnection()
        } else {
            print("⚠️ NFC: onTagConnected() called but no pending operation found")
        }
    }
    
    /**
     * Send APDU command to chip
     * Assumes session is already started and tag is connected
     */
    func sendAPDU(_ apdu: Data, completion: @escaping (Result<Data, Error>) -> Void) {
        guard let tag = currentTag else {
            print("🔴 NFC: sendAPDU() called but currentTag is nil")
            completion(.failure(NSError(domain: "NFCService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No tag connected. Call startSessionAndWaitForTag() first."])))
            return
        }
        
        print("🔵 NFC: sendAPDU() called, sending APDU command...")
        executeAPDUOnTag(tag, apdu: apdu, completion: completion)
    }
    
    /**
     * Execute APDU on specific tag
     * According to Apple's CoreNFC documentation, completion handlers are called on the main queue
     */
    private func executeAPDUOnTag(_ tag: NFCISO7816Tag, apdu: Data, completion: @escaping (Result<Data, Error>) -> Void) {
        guard let apduCommand = NFCISO7816APDU(data: apdu) else {
            print("🔴 NFC: Failed to create NFCISO7816APDU from data")
            DispatchQueue.main.async {
                completion(.failure(NSError(domain: "NFCService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid APDU command"])))
            }
            return
        }
        
        print("🔵 NFC: Sending APDU command to tag...")
        tag.sendCommand(
            apdu: apduCommand,
            completionHandler: { (response: Data, sw1: UInt8, sw2: UInt8, error: Error?) in
                if let error = error {
                    print("🔴 NFC: APDU command failed - \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }
                
                let statusWord = UInt16(sw1) << 8 | UInt16(sw2)
                print("✅ NFC: APDU command completed - Status: 0x\(String(format: "%04x", statusWord))")
                
                // Combine response data with status word
                var fullResponse = response
                fullResponse.append(sw1)
                fullResponse.append(sw2)
                
                completion(.success(fullResponse))
            }
        )
    }
    
    /**
     * Read public key from chip
     */
    func readPublicKey(completion: @escaping (Result<String, Error>) -> Void) {
        print("🔵 NFC: readPublicKey() called")
        // Store completion for when tag connects
        readPublicKeyCompletion = completion
        currentTag = nil
        
        // Start session - tag connection will be handled in delegate
        startSession()
    }
    
    /**
     * Read public key after tag is connected
     * Follows Infineon SECORA reference implementation pattern:
     * 1. SELECT applet
     * 2. GET_KEY_INFO
     */
    private func readPublicKeyAfterConnection() {
        print("🔵 NFC: readPublicKeyAfterConnection() called")
        guard let completion = readPublicKeyCompletion else {
            print("⚠️ NFC: readPublicKeyAfterConnection() called but no completion handler")
            return
        }
        // Step 1: Select applet (required before any other commands)
        print("🔵 NFC: Sending SELECT applet command...")
        let selectCommand = APDUCommands.selectApplet()
        
        sendAPDU(selectCommand) { [weak self] result in
            guard let self = self else {
                completion(.failure(NSError(domain: "NFCService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Service deallocated"])))
                return
            }
            
            switch result {
            case .success(let selectResponse):
                let selectAPDU = APDUResponse(rawResponse: selectResponse)
                guard let apdu = selectAPDU, apdu.isSuccess else {
                    let statusHex = selectAPDU != nil ? String(format: "0x%04x", selectAPDU!.statusWord) : "unknown"
                    let error = NSError(domain: "NFCService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to select applet. Status: \(statusHex)"])
                    completion(.failure(error))
                    self.stopSession()
                    return
                }
                
                // Step 2: Get key info
                let getKeyInfoCommand = APDUCommands.getKeyInfo()
                
                self.sendAPDU(getKeyInfoCommand) { result in
                    switch result {
                    case .success(let keyResponse):
                        let keyAPDU = APDUResponse(rawResponse: keyResponse)
                        guard let apdu = keyAPDU, apdu.isSuccess else {
                            let statusHex = keyAPDU != nil ? String(format: "0x%04x", keyAPDU!.statusWord) : "unknown"
                            let error = NSError(domain: "NFCService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get key info. Status: \(statusHex)"])
                            completion(.failure(error))
                            self.stopSession()
                            return
                        }
                        
                        guard let publicKey = APDUHandler.parsePublicKey(from: apdu.data) else {
                            let error = NSError(domain: "NFCService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse public key"])
                            completion(.failure(error))
                            self.stopSession()
                            return
                        }
                        
                        completion(.success(publicKey))
                        self.readPublicKeyCompletion = nil
                        self.stopSession()
                        
                    case .failure(let error):
                        completion(.failure(error))
                        self.readPublicKeyCompletion = nil
                        self.stopSession()
                    }
                }
                
            case .failure(let error):
                completion(.failure(error))
                self.readPublicKeyCompletion = nil
                self.stopSession()
            }
        }
    }
    
    /**
     * Sign message with chip
     */
    func signMessage(messageHash: Data, completion: @escaping (Result<(r: String, s: String, recoveryId: Int), Error>) -> Void) {
        print("🔵 NFC: signMessage() called with hash: \(bytesToHex(messageHash))")
        // Store completion and message hash for when tag connects
        signMessageCompletion = completion
        signMessageHash = messageHash
        currentTag = nil
        
        // Start session - tag connection will be handled in delegate
        startSession()
    }
    
    /**
     * Sign message after tag is connected
     * Follows Infineon SECORA reference implementation pattern:
     * 1. SELECT applet
     * 2. GENERATE_SIGNATURE
     */
    private func signMessageAfterConnection() {
        print("🔵 NFC: signMessageAfterConnection() called")
        guard let completion = signMessageCompletion,
              let messageHash = signMessageHash else {
            print("⚠️ NFC: signMessageAfterConnection() called but no completion handler or message hash")
            return
        }
        // Step 1: Select applet (required before any other commands)
        print("🔵 NFC: Sending SELECT applet command...")
        let selectCommand = APDUCommands.selectApplet()
        
        sendAPDU(selectCommand) { [weak self] result in
            guard let self = self else {
                completion(.failure(NSError(domain: "NFCService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Service deallocated"])))
                return
            }
            
            switch result {
            case .success(let selectResponse):
                let selectAPDU = APDUResponse(rawResponse: selectResponse)
                guard let apdu = selectAPDU, apdu.isSuccess else {
                    let statusHex = selectAPDU != nil ? String(format: "0x%04x", selectAPDU!.statusWord) : "unknown"
                    let error = NSError(domain: "NFCService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to select applet. Status: \(statusHex)"])
                    completion(.failure(error))
                    self.stopSession()
                    return
                }
                
                // Step 2: Generate signature
                let signCommand = APDUCommands.generateSignature(messageHash: messageHash)
                
                self.sendAPDU(signCommand) { result in
                    switch result {
                    case .success(let signResponse):
                        let signAPDU = APDUResponse(rawResponse: signResponse)
                        guard let apdu = signAPDU, apdu.isSuccess else {
                            let statusHex = signAPDU != nil ? String(format: "0x%04x", signAPDU!.statusWord) : "unknown"
                            let error = NSError(domain: "NFCService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to generate signature. Status: \(statusHex)"])
                            completion(.failure(error))
                            self.stopSession()
                            return
                        }
                        
                        guard let signature = APDUHandler.parseSignature(from: apdu.data) else {
                            let error = NSError(domain: "NFCService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse signature"])
                            completion(.failure(error))
                            self.stopSession()
                            return
                        }
                        
                        completion(.success((r: signature.r, s: signature.s, recoveryId: signature.recoveryId)))
                        self.signMessageCompletion = nil
                        self.signMessageHash = nil
                        self.stopSession()
                        
                    case .failure(let error):
                        completion(.failure(error))
                        self.signMessageCompletion = nil
                        self.signMessageHash = nil
                        self.stopSession()
                    }
                }
                
            case .failure(let error):
                completion(.failure(error))
                self.signMessageCompletion = nil
                self.signMessageHash = nil
                self.stopSession()
            }
        }
    }
    
    func readNDEFMessage(completion: @escaping (Result<ScannedItem?, Error>) -> Void) {
        guard NFCTagReaderSession.readingAvailable else {
            completion(.failure(NSError(domain: "NFCService", code: -1, userInfo: [NSLocalizedDescriptionKey: "NFC not available"])))
            return
        }
        
        let ndefSession = NFCNDEFReaderSession(delegate: NDEFSessionDelegate(completion: completion), queue: nil, invalidateAfterFirstRead: true)
        ndefSession.alertMessage = "Hold your device near the NFC tag"
        ndefSession.begin()
    }
}

class NDEFSessionDelegate: NSObject, NFCNDEFReaderSessionDelegate {
    let completion: (Result<ScannedItem?, Error>) -> Void
    
    init(completion: @escaping (Result<ScannedItem?, Error>) -> Void) {
        self.completion = completion
        super.init()
    }
    
    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        for message in messages {
            for record in message.records {
                if record.typeNameFormat == .nfcWellKnown,
                   let payload = String(data: record.payload, encoding: .utf8),
                   let url = URL(string: payload) {
                    
                    let scannedItem = parseURL(url)
                    // Session will auto-invalidate with invalidateAfterFirstRead: true
                    completion(.success(scannedItem))
                    return
                }
            }
        }
        
        // Session will auto-invalidate with invalidateAfterFirstRead: true
        completion(.success(nil))
    }
    
    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        if let nfcError = error as? NFCReaderError,
           nfcError.code == .readerSessionInvalidationErrorUserCanceled {
            completion(.success(nil))
        } else {
            completion(.failure(error))
        }
    }
    
    private func parseURL(_ url: URL) -> ScannedItem? {
        guard url.scheme == "nfmerch" || url.scheme == "stellarmerch" else {
            return nil
        }
        
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        if pathComponents.count >= 2 && pathComponents[0] == "item" {
            let contractId = pathComponents[1]
            let tokenId = pathComponents.count > 2 ? pathComponents[2] : nil
            return ScannedItem(contractId: contractId, tokenId: tokenId)
        }
        
        return nil
    }
}
