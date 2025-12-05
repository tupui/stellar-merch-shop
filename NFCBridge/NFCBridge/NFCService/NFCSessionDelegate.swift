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
        // Session became active - can display UI if needed
    }
    
    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard let firstTag = tags.first else {
            session.invalidate(errorMessage: "No tag detected")
            return
        }
        
        // Only handle ISO 7816 tags (SECORA chips)
        guard case .iso7816(let iso7816Tag) = firstTag else {
            session.invalidate(errorMessage: "Unsupported tag type. SECORA chips use ISO 7816.")
            return
        }
        
        session.connect(to: firstTag) { [weak self] (error: Error?) in
            guard let self = self, let service = self.service else { return }
            
            if let error = error {
                session.invalidate(errorMessage: "Connection failed: \(error.localizedDescription)")
                service.delegate?.nfcService(service, didFailWithError: error)
                return
            }
            
            // Tag connected, notify service with ISO 7816 tag
            service.tagConnected = iso7816Tag
        }
    }
    
    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        // Session invalidated (user cancelled, error, etc.)
        service?.sessionInvalidated(error: error)
    }
}
