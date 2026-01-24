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
import OSLog

/// Helper class that manages the NFC card detection events
final class NFCHelper: NSObject, NFCTagReaderSessionDelegate {
    let TAG: String = "NFCHelper"
    
    /// Background queue for NFC delegate callbacks (per Apple best practices)
    private let nfcQueue = DispatchQueue(label: "com.consulting-manao.chimp.nfc", qos: .userInitiated)
    
    /// Stores the reader session handle
    var readerSession: NFCTagReaderSession?
    /// Event handler which is called when the tag detection action is completed
    var OnTagEvent: ((Bool, NFCISO7816Tag?, NFCTagReaderSession?, String?) -> ())?
    
    /// Timeout timer for 60-second session limit
    private var timeoutTimer: Timer?
    
    /// Maximum session duration (60 seconds per Apple's limit)
    private let maxSessionDuration: TimeInterval = 60.0
    
    // MARK: - NFC Reader Session Events
    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        Logger.logDebug("ReaderSession: Active", category: .nfc)
    }
    
    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        Logger.logDebug("ReaderSession: Invalidated", category: .nfc)
        
        // Cancel timeout timer
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        
        // Clear session reference
        readerSession = nil
        
        guard let OnTagEvent = OnTagEvent else {
            return
        }
        
        // Comprehensive error handling per Apple best practices
        if let readerError = error as? NFCReaderError {
            let errorCode = readerError.code
            Logger.logDebug("ReaderSession: Error code: \(errorCode.rawValue)", category: .nfc)
            
            // Handle different error cases
            switch errorCode {
            case .readerSessionInvalidationErrorFirstNDEFTagRead:
                // Success case - tag was read successfully
                Logger.logDebug("ReaderSession: Tag read successfully", category: .nfc)
                return
                
            case .readerSessionInvalidationErrorUserCanceled:
                // User canceled - not an error
                Logger.logDebug("ReaderSession: User canceled", category: .nfc)
                return
                
            case .readerSessionInvalidationErrorSessionTerminatedUnexpectedly:
                // Session terminated unexpectedly
                Logger.logWarning("ReaderSession: Session terminated unexpectedly", category: .nfc)
                DispatchQueue.main.async {
                    OnTagEvent(false, nil, nil, "NFC session ended unexpectedly. Please try again.")
                }
                
            case .readerSessionInvalidationErrorSystemIsBusy:
                // System is busy
                Logger.logWarning("ReaderSession: System is busy", category: .nfc)
                DispatchQueue.main.async {
                    OnTagEvent(false, nil, nil, "NFC system is busy. Please try again.")
                }
                
            case .readerSessionInvalidationErrorSessionTimeout:
                // Session timeout (60 seconds)
                Logger.logWarning("ReaderSession: Session timeout", category: .nfc)
                DispatchQueue.main.async {
                    OnTagEvent(false, nil, nil, "NFC session timed out. Please try again.")
                }
                
            default:
                // Other errors
                Logger.logError("ReaderSession: Unknown error: \(error.localizedDescription)", category: .nfc)
                DispatchQueue.main.async {
                    OnTagEvent(false, nil, nil, "NFC session failed. Please try again.")
                }
            }
        } else {
            // Non-NFCReaderError
            Logger.logError("ReaderSession: Non-NFC error: \(error.localizedDescription)", category: .nfc)
            DispatchQueue.main.async {
                OnTagEvent(false, nil, nil, "NFC operation failed. Please try again.")
            }
        }
    }
    
    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        Logger.logDebug("ReaderSession: Tag detected", category: .nfc)

        // Cancel timeout timer since we detected a tag
        timeoutTimer?.invalidate()
        timeoutTimer = nil

        if tags.count > 1 {
            Logger.logWarning("ReaderSession: Multiple tags found", category: .nfc)
            session.alertMessage = "Multiple tags found. Please use only one tag."
            DispatchQueue.main.async {
                if let OnTagEvent = self.OnTagEvent {
                    OnTagEvent(false, nil, nil, "Multiple tags found. Please use only one tag.")
                }
            }
            EndSession()
            return
        }

        guard let firstTag = tags.first else {
            Logger.logWarning("ReaderSession: No tags in array", category: .nfc)
            DispatchQueue.main.async {
                if let OnTagEvent = self.OnTagEvent {
                    OnTagEvent(false, nil, nil, "No tag detected")
                }
            }
            return
        }

        if case let NFCTag.iso7816(tag) = firstTag {
            session.connect(to: firstTag) { [weak self] (error: Error?) in
                guard let self = self else { return }
                if let error = error {
                    Logger.logError("ReaderSession: Connection error: \(error.localizedDescription)", category: .nfc)
                    DispatchQueue.main.async {
                        if let OnTagEvent = self.OnTagEvent {
                            OnTagEvent(false, nil, nil, "Failed to connect to NFC tag. Please try again.")
                        }
                    }
                } else {
                    Logger.logDebug("ReaderSession: Tag connected successfully", category: .nfc)

                    // APDU operation - chip detected, user should hold steady
                    if let OnTagEvent = self.OnTagEvent {
                        session.alertMessage = "Chip detected! Hold steady while processing..."
                        DispatchQueue.main.async {
                            OnTagEvent(true, tag, session, nil)
                        }
                    }
                }
            }
        } else {
            Logger.logWarning("ReaderSession: Tag is not ISO7816 compatible", category: .nfc)
            session.alertMessage = "Tag is not compatible"
            DispatchQueue.main.async {
                if let OnTagEvent = self.OnTagEvent {
                    OnTagEvent(false, nil, nil, "Tag is not ISO7816 compatible")
                }
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
            Logger.logWarning("ReaderSession: NFC not available on this device", category: .nfc)
            return
        }
        
        // Prevent multiple active sessions (Apple best practice)
        if readerSession != nil {
            Logger.logWarning("ReaderSession: Session already active, invalidating previous session", category: .nfc)
            EndSession()
        }
        
        // Create session with background queue (Apple best practice)
        readerSession = NFCTagReaderSession(
            pollingOption: [.iso14443],
            delegate: self,
            queue: nfcQueue
        )
        
        readerSession?.alertMessage = "Hold your device near the NFC chip"
        readerSession?.begin()
        
        Logger.logDebug("ReaderSession: Begin", category: .nfc)
        
        // Set up timeout timer for 60-second limit (Apple's maximum) on main run loop
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: maxSessionDuration, repeats: false) { [weak self] _ in
            guard let self = self, let session = self.readerSession else { return }
            Logger.logWarning("ReaderSession: Timeout reached (60 seconds)", category: .nfc)
            session.invalidate(errorMessage: "Session timed out. Please try again.")
        }
        // Ensure timer is on main run loop
        if let timer = timeoutTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }
    
    /// Invalidates the NFC reader session
    func EndSession(){
        // Cancel timeout timer
        timeoutTimer?.invalidate()
        timeoutTimer = nil

        readerSession?.invalidate()
        readerSession = nil

        Logger.logDebug("ReaderSession: End", category: .nfc)
    }
}
