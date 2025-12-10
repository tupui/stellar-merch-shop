/**
 * NFC Service
 * Manages NFCISO7816TagReaderSession and APDU communication with SECORA chip
 */

import Foundation
import CoreNFC

class NFCService {
    weak var delegate: NFCServiceDelegate?
    
    private var session: NFCTagReaderSession?
    private var sessionDelegate: NFCSessionDelegate?
    private var currentTag: NFCISO7816Tag?
    var tagConnected: NFCISO7816Tag? {
        get { currentTag }
        set {
            currentTag = newValue
            if newValue != nil {
                // Tag connected, can proceed with operations
                tagConnectedCallback?()
            }
        }
    }
    
    private var tagConnectedCallback: (() -> Void)?
    
    /**
     * Start NFC session
     * Uses NFCTagReaderSession with ISO 14443 polling for ISO 7816 tags (SECORA chips)
     * MUST be called on main thread
     */
    func startSession() {
        // Ensure we're on the main thread
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.startSession()
            }
            return
        }
        
        // Check if NFC is available - use NFCTagReaderSession.readingAvailable for ISO 7816 tags
        // NFCNDEFReaderSession.readingAvailable might not be the right check for ISO 7816
        
        // Check if running on simulator
        #if targetEnvironment(simulator)
        let error = NSError(domain: "NFCService", code: -1, userInfo: [NSLocalizedDescriptionKey: "NFC is not available on iOS Simulator. Please run on a physical device."])
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.nfcService(self, didFailWithError: error)
        }
        return
        #endif
        
        guard NFCTagReaderSession.readingAvailable else {
            var errorMessage = "NFC not available on this device. "
            errorMessage += "Possible causes:\n"
            errorMessage += "1. NFC is disabled in Settings\n"
            errorMessage += "2. Device doesn't support NFC\n"
            errorMessage += "3. App doesn't have NFC capability enabled\n"
            errorMessage += "4. Entitlements file not properly configured\n"
            errorMessage += "5. NFC Tag Reading requires a paid Apple Developer account (personal teams don't support this capability)"
            
            let error = NSError(domain: "NFCService", code: -1, userInfo: [NSLocalizedDescriptionKey: errorMessage])
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.nfcService(self, didFailWithError: error)
            }
            return
        }
        
        // Don't start a new session if one is already active
        if session != nil {
            return
        }
        
        // Use NFCTagReaderSession with ISO 14443 polling for ISO 7816 tags
        // This will show the iOS NFC scan UI automatically
        // Keep reference to delegate to prevent deallocation
        sessionDelegate = NFCSessionDelegate(service: self)
        session = NFCTagReaderSession(
            pollingOption: .iso14443,
            delegate: sessionDelegate!,
            queue: DispatchQueue.main  // Use main queue for UI updates
        )
        
        guard let session = session else {
            let error = NSError(domain: "NFCService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create NFC session"])
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.nfcService(self, didFailWithError: error)
            }
            return
        }
        
        session.alertMessage = "Hold your device near the NFC chip"
        session.begin()
    }
    
    /**
     * Stop NFC session
     */
    func stopSession() {
        session?.invalidate(errorMessage: "Session completed")
        session = nil
        sessionDelegate = nil
        currentTag = nil
        tagConnectedCallback = nil
    }
    
    /**
     * Session was invalidated
     */
    func sessionInvalidated(error: Error) {
        currentTag = nil
        session = nil
        sessionDelegate = nil
        tagConnectedCallback = nil
        
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
     * Start NFC session and wait for tag connection
     * Call this before sending APDU commands
     */
    func startSessionAndWaitForTag(completion: @escaping (Result<Void, Error>) -> Void) {
        // If tag already connected, return immediately
        if currentTag != nil {
            completion(.success(()))
            return
        }
        
        // Store completion for when tag connects
        tagConnectedCallback = { [weak self] in
            if let self = self, self.currentTag != nil {
                completion(.success(()))
            } else {
                completion(.failure(NSError(domain: "NFCService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Tag connection failed - tag is nil"])))
            }
        }
        
        // Add timeout for tag connection (30 seconds)
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self = self else { return }
            if self.currentTag == nil && self.tagConnectedCallback != nil {
                self.tagConnectedCallback = nil
                self.stopSession()
                completion(.failure(NSError(domain: "NFCService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Timeout waiting for NFC tag. Please try again."])))
            }
        }
        
        startSession()
    }
    
    /**
     * Send APDU command to chip
     * Assumes session is already started and tag is connected
     */
    func sendAPDU(_ apdu: Data, completion: @escaping (Result<Data, Error>) -> Void) {
        guard let tag = currentTag else {
            completion(.failure(NSError(domain: "NFCService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No tag connected. Call startSessionAndWaitForTag() first."])))
            return
        }
        
        executeAPDUOnTag(tag, apdu: apdu, completion: completion)
    }
    
    /**
     * Execute APDU after tag is connected
     */
    private func executeAPDU(_ apdu: Data, completion: @escaping (Result<Data, Error>) -> Void) {
        guard let tag = currentTag else {
            completion(.failure(NSError(domain: "NFCService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Tag connection lost"])))
            return
        }
        
        executeAPDUOnTag(tag, apdu: apdu, completion: completion)
    }
    
    /**
     * Execute APDU on specific tag
     * According to Apple's CoreNFC documentation, completion handlers are called on the main queue
     */
    private func executeAPDUOnTag(_ tag: NFCISO7816Tag, apdu: Data, completion: @escaping (Result<Data, Error>) -> Void) {
        guard let apduCommand = NFCISO7816APDU(data: apdu) else {
            DispatchQueue.main.async {
                completion(.failure(NSError(domain: "NFCService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid APDU command"])))
            }
            return
        }
        
        tag.sendCommand(
            apdu: apduCommand,
            completionHandler: { (response: Data, sw1: UInt8, sw2: UInt8, error: Error?) in
                // Completion handler is already called on main queue per Apple's documentation
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
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
        // Reset any existing tag connection
        currentTag = nil
        
        // Start session and wait for tag
        startSessionAndWaitForTag { [weak self] result in
            guard let self = self else {
                completion(.failure(NSError(domain: "NFCService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Service deallocated"])))
                return
            }
            
            switch result {
            case .success:
                // Tag connected, now send APDU commands
                self.readPublicKeyAfterConnection(completion: completion)
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    /**
     * Read public key after tag is connected
     * Follows Infineon SECORA reference implementation pattern:
     * 1. SELECT applet
     * 2. GET_KEY_INFO
     */
    private func readPublicKeyAfterConnection(completion: @escaping (Result<String, Error>) -> Void) {
        // Step 1: Select applet (required before any other commands)
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
                        // Stop session after successful read
                        self.stopSession()
                        
                    case .failure(let error):
                        completion(.failure(error))
                        self.stopSession()
                    }
                }
                
            case .failure(let error):
                completion(.failure(error))
                self.stopSession()
            }
        }
    }
    
    /**
     * Sign message with chip
     */
    func signMessage(messageHash: Data, completion: @escaping (Result<(r: String, s: String, recoveryId: Int), Error>) -> Void) {
        // Start session and wait for tag
        startSessionAndWaitForTag { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success:
                // Tag connected, now send APDU commands
                self.signMessageAfterConnection(messageHash: messageHash, completion: completion)
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    /**
     * Sign message after tag is connected
     * Follows Infineon SECORA reference implementation pattern:
     * 1. SELECT applet
     * 2. GENERATE_SIGNATURE
     */
    private func signMessageAfterConnection(messageHash: Data, completion: @escaping (Result<(r: String, s: String, recoveryId: Int), Error>) -> Void) {
        // Step 1: Select applet (required before any other commands)
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
                        // Stop session after successful signature
                        self.stopSession()
                        
                    case .failure(let error):
                        completion(.failure(error))
                        self.stopSession()
                    }
                }
                
            case .failure(let error):
                completion(.failure(error))
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
