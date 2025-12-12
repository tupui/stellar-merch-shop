/*
 MIT License
 
 Copyright (c) 2020 Infineon Technologies AG
 
 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:
 
 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE.
 */

import Foundation
import CoreNFC

/// Helper class that manages the NFC card detection events
class NFCHelper: NSObject, NFCTagReaderSessionDelegate {
    let TAG: String = "NFCHelper"
    
    /// Background queue for NFC delegate callbacks (per Apple best practices)
    private let nfcQueue = DispatchQueue(label: "com.stellarmerch.nfc", qos: .userInitiated)
    
    /// Stores the reader session handle
    var reader_session: NFCTagReaderSession?
    /// Event handler which is called when the tag detection action is completed
    var OnTagEvent: ((Bool, NFCISO7816Tag?, NFCTagReaderSession?, String?) -> ())?
    
    /// Timeout timer for 60-second session limit
    private var timeoutTimer: Timer?
    
    /// Maximum session duration (60 seconds per Apple's limit)
    private let maxSessionDuration: TimeInterval = 60.0
    
    // MARK: - NFC Reader Session Events
    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        print(TAG + ": ReaderSession: Active")
    }
    
    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        print(TAG + ": ReaderSession: Invalidated")
        
        // Cancel timeout timer
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        
        // Clear session reference
        reader_session = nil
        
        guard let OnTagEvent = OnTagEvent else {
            return
        }
        
        // Comprehensive error handling per Apple best practices
        if let readerError = error as? NFCReaderError {
            let errorCode = readerError.code
            print(TAG + ": ReaderSession: Error code: \(errorCode.rawValue)")
            
            // Handle different error cases
            switch errorCode {
            case .readerSessionInvalidationErrorFirstNDEFTagRead:
                // Success case - tag was read successfully
                print(TAG + ": ReaderSession: Tag read successfully")
                return
                
            case .readerSessionInvalidationErrorUserCanceled:
                // User canceled - not an error
                print(TAG + ": ReaderSession: User canceled")
                return
                
            case .readerSessionInvalidationErrorSessionTerminatedUnexpectedly:
                // Session terminated unexpectedly
                print(TAG + ": ReaderSession: Session terminated unexpectedly")
                DispatchQueue.main.async {
                    OnTagEvent(false, nil, nil, "NFC session ended unexpectedly. Please try again.")
                }
                
            case .readerSessionInvalidationErrorSystemIsBusy:
                // System is busy
                print(TAG + ": ReaderSession: System is busy")
                DispatchQueue.main.async {
                    OnTagEvent(false, nil, nil, "NFC system is busy. Please try again.")
                }
                
            case .readerSessionInvalidationErrorSessionTimeout:
                // Session timeout (60 seconds)
                print(TAG + ": ReaderSession: Session timeout")
                DispatchQueue.main.async {
                    OnTagEvent(false, nil, nil, "NFC session timed out. Please try again.")
                }
                
            default:
                // Other errors
                print(TAG + ": ReaderSession: Unknown error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    OnTagEvent(false, nil, nil, "NFC error: \(error.localizedDescription)")
                }
            }
        } else {
            // Non-NFCReaderError
            print(TAG + ": ReaderSession: Non-NFC error: \(error.localizedDescription)")
            DispatchQueue.main.async {
                OnTagEvent(false, nil, nil, error.localizedDescription)
            }
        }
    }
    
    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        print(TAG + ": ReaderSession: Tag detected")
        
        // Cancel timeout timer since we detected a tag
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        
        guard let OnTagEvent = OnTagEvent else {
            return
        }
        
        if tags.count > 1 {
            print(TAG + ": ReaderSession: Multiple tags found")
            session.alertMessage = "Multiple tags found. Please use only one tag."
            DispatchQueue.main.async {
                OnTagEvent(false, nil, nil, "Multiple tags found. Please use only one tag.")
            }
            EndSession()
            return
        }
        
        guard let firstTag = tags.first else {
            print(TAG + ": ReaderSession: No tags in array")
            DispatchQueue.main.async {
                OnTagEvent(false, nil, nil, "No tag detected")
            }
            return
        }
        
        if case let NFCTag.iso7816(tag) = firstTag {
            session.connect(to: firstTag) { [weak self] (error: Error?) in
                guard let self = self else { return }
                if let error = error {
                    print(self.TAG + ": ReaderSession: Connection error: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self.OnTagEvent?(false, nil, nil, "Failed to connect to tag: \(error.localizedDescription)")
                    }
                } else {
                    print(self.TAG + ": ReaderSession: Tag connected successfully")
                    // Trigger the tag operation event on main thread for UI updates
                    DispatchQueue.main.async {
                        self.OnTagEvent?(true, tag, session, nil)
                    }
                }
            }
        } else {
            print(TAG + ": ReaderSession: Tag is not ISO7816 compatible")
            session.alertMessage = "Tag is not compatible"
            DispatchQueue.main.async {
                OnTagEvent(false, nil, nil, "Tag is not ISO7816 compatible")
            }
            EndSession()
        }
    }
    
    // MARK: - Helper methods
    /// Checks if the NFC reader is supported by this device
    /// - Returns: Flag indicating true if NFC reader is supported
    func IsNFCReaderAvailable() -> Bool{
        return NFCTagReaderSession.readingAvailable
    }
    
    /// Begins the ISO14443 reader session
    func BeginSession() {
        // Check if device supports NFC reading
        guard IsNFCReaderAvailable() else {
            print(TAG + ": ReaderSession: NFC not available on this device")
            return
        }
        
        // Prevent multiple active sessions (Apple best practice)
        if reader_session != nil {
            print(TAG + ": ReaderSession: Session already active, invalidating previous session")
            EndSession()
        }
        
        // Create session with background queue (Apple best practice)
        reader_session = NFCTagReaderSession(
            pollingOption: [.iso14443],
            delegate: self,
            queue: nfcQueue
        )
        
        reader_session?.alertMessage = "Hold your device near the NFC chip"
        reader_session?.begin()
        
        print(TAG + ": ReaderSession: Begin")
        
        // Set up timeout timer for 60-second limit (Apple's maximum)
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: maxSessionDuration, repeats: false) { [weak self] _ in
            guard let self = self, let session = self.reader_session else { return }
            print(self.TAG + ": ReaderSession: Timeout reached (60 seconds)")
            session.invalidate(errorMessage: "Session timed out. Please try again.")
        }
    }
    
    /// Invalidates the NFC reader session
    func EndSession(){
        // Cancel timeout timer
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        
        reader_session?.invalidate()
        reader_session = nil
        
        print(TAG + ": ReaderSession: End")
    }
}
