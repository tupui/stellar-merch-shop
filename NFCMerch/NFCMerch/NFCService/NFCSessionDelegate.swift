/**
 * NFCTagReaderSession Delegate
 * Handles NFC tag detection and communication for ISO 7816 tags (SECORA chips)
 */

import Foundation
import CoreNFC

protocol NFCServiceDelegate: AnyObject {
    func nfcService(_ service: NFCService, didReceivePublicKey publicKey: String)
    func nfcService(_ service: NFCService, didReceiveSignature r: String, s: String, recoveryId: Int)
    func nfcService(_ service: NFCService, didFailWithError error: Error)
}

class NFCSessionDelegate: NSObject, NFCTagReaderSessionDelegate {
    weak var service: NFCService?
    
    init(service: NFCService) {
        self.service = service
        super.init()
    }
    
    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        print("✅ NFC: tagReaderSessionDidBecomeActive called - session is now active")
        print("🔵 NFC: Session delegate in didBecomeActive: \(session.delegate != nil ? "exists" : "nil")")
        print("🔵 NFC: Service reference in didBecomeActive: \(service != nil ? "exists" : "nil")")
        
        // Set alert message now that session is active (better iOS compatibility)
        // Use a simple string to avoid any potential issues
        let alertMsg = "Hold your device near the NFC chip"
        session.alertMessage = alertMsg
        print("✅ NFC: Alert message set in didBecomeActive: '\(alertMsg)'")
        
        // Verify session is still valid after setting alert message
        print("🔵 NFC: Session state after alert message - delegate: \(session.delegate != nil ? "exists" : "nil")")
        
        print("🔵 NFC: Session is active, waiting for tag detection...")
        print("🔵 NFC: Make sure chip is held steady on the back of the device near the top")
    }
    
    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        print("✅ NFC: tagReaderSession didDetect called with \(tags.count) tag(s)")
        
        session.alertMessage = "Tag detected, connecting..."
        
        guard let firstTag = tags.first else {
            print("⚠️ NFC: didDetect called but tags array is empty")
            return
        }
        
        // Log tag type
        switch firstTag {
        case .iso7816:
            print("✅ NFC: Tag type is ISO 7816 (SECORA chip)")
        case .feliCa:
            print("⚠️ NFC: Tag type is FeliCa (not supported)")
        case .iso15693:
            print("⚠️ NFC: Tag type is ISO 15693 (not supported)")
        case .miFare:
            print("⚠️ NFC: Tag type is MiFare (not supported)")
        @unknown default:
            print("⚠️ NFC: Tag type is unknown")
        }
        
        // We only support ISO 7816 tags (SECORA chips)
        guard case .iso7816(let iso7816Tag) = firstTag else {
            print("🔴 NFC: Unsupported tag type detected")
            session.invalidate(errorMessage: "Unsupported tag type. Please use a SECORA chip.")
            let error = NSError(domain: "NFCService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unsupported tag type. Expected ISO 7816."])
            if let service = service {
                service.delegate?.nfcService(service, didFailWithError: error)
            }
            return
        }
        // Log detected AID (if available)
        let selectedAID = iso7816Tag.initialSelectedAID
        if selectedAID.isEmpty {
            print("⚠️ NFC: initialSelectedAID unavailable on detected tag")
        } else {
            print("🔵 NFC: Detected tag initialSelectedAID: \(selectedAID)")
        }
        
        print("🔵 NFC: Connecting to ISO 7816 tag...")
        // Connect to the ISO 7816 tag
        session.connect(to: firstTag) { [weak self] (error: Error?) in
            guard let self = self, let service = self.service else {
                print("⚠️ NFC: Service deallocated during connection")
                return
            }
            
            if let error = error {
                print("🔴 NFC: Connection failed - \(error.localizedDescription)")
                session.invalidate(errorMessage: "Connection failed: \(error.localizedDescription)")
                service.delegate?.nfcService(service, didFailWithError: error)
                return
            }
            
            print("✅ NFC: Tag connected successfully!")
            // Tag connected - store it and proceed with operation
            service.currentTag = iso7816Tag
            print("🔵 NFC: Calling service.onTagConnected()...")
            service.onTagConnected()
        }
    }
    
    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        print("🔴 NFC: didInvalidateWithError called!")
        print("🔴 NFC: ========== SESSION INVALIDATION ==========")
        
        // Log session state
        print("🔴 NFC: Session delegate exists: \(session.delegate != nil ? "yes" : "no")")
        print("🔴 NFC: Service reference exists: \(service != nil ? "yes" : "no")")
        
        // Detailed error information
        if let nfcError = error as? NFCReaderError {
            let codeName: String
            switch nfcError.code {
            case .readerSessionInvalidationErrorUserCanceled:
                codeName = "UserCanceled"
            case .readerSessionInvalidationErrorSessionTimeout:
                codeName = "SessionTimeout"
            case .readerSessionInvalidationErrorSystemIsBusy:
                codeName = "SystemIsBusy"
            case .readerSessionInvalidationErrorFirstNDEFTagRead:
                codeName = "FirstNDEFTagRead"
            case .readerSessionInvalidationErrorSessionTerminatedUnexpectedly:
                codeName = "SessionTerminatedUnexpectedly"
            @unknown default:
                codeName = "Unknown(\(nfcError.code.rawValue))"
            }
            print("🔴 NFC: Error type: NFCReaderError")
            print("🔴 NFC: Error code: \(codeName) (raw: \(nfcError.code.rawValue))")
            print("🔴 NFC: Error description: \(error.localizedDescription)")
            
            // Log userInfo if available
            if let nsError = error as NSError? {
                print("🔴 NFC: Error domain: \(nsError.domain)")
                print("🔴 NFC: Error code: \(nsError.code)")
                if let userInfo = nsError.userInfo as? [String: Any], !userInfo.isEmpty {
                    print("🔴 NFC: Error userInfo: \(userInfo)")
                }
            }
        } else {
            print("🔴 NFC: Error type: \(type(of: error))")
            print("🔴 NFC: Error description: \(error.localizedDescription)")
            
            if let nsError = error as NSError? {
                print("🔴 NFC: Error domain: \(nsError.domain)")
                print("🔴 NFC: Error code: \(nsError.code)")
                if let userInfo = nsError.userInfo as? [String: Any], !userInfo.isEmpty {
                    print("🔴 NFC: Error userInfo: \(userInfo)")
                }
            }
        }
        
        print("🔴 NFC: ===========================================")
        service?.sessionInvalidated(error: error)
    }
}
