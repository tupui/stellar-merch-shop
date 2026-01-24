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

/** Manages to APDU exchange for reading the public-key from the Blockchain Seurity2Go card
    1) SELECT_APPLICATION
    2) GET_KEY_INFO
    3) If key not available at index, GENERATE_KEY multiple times until selected key index is generated and then GET_KEY_INFO
*/
class BlockchainCommandHandler: CommandHandler {
    let TAG: String = "BlockchainCommandHandler"

    // Command APDU definitions
    let APDU_SELECT = Data(_: [0x00,0xA4,0x04,0x00,0x0D,0xD2,0x76,0x00,0x00,0x04,0x15,
                               0x02,0x00,0x01,0x00,0x00,0x00,0x01,0x00])
    let ADPU_GET_KEY_INFO = Data(_: [0x00,0x16,0x00,0x00,0x00])
    let ADPU_GENERATE_KEY = Data(_: [0x00,0x02,0x00,0x00,0x01])
    
    /// Action completion handler, which is called when the command excahges are completed
    var OnActionCompleted: ((Bool, Data?, String?, NFCTagReaderSession) -> ())?
    var keyIndex: UInt8 = 0x01
    var messageDigest: Data?
    
    /// Triggers the APDU exchanges to get the public-key from the card
    /// - Parameters:
    ///   - keyIndex: Key index of the public-key. Must be >0.
    ///   - completion_handler: Handler method to be called when the action is completed
    func getKey(keyIndex: UInt8, completion_handler: @escaping (Bool, Data?,String?,NFCTagReaderSession) -> Void) {
        self.keyIndex = keyIndex
        self.OnActionCompleted = completion_handler
        
        SelectApplication()
    }
    
    // MARK: - Command handler - SELECT_APPLICATION
    /// Sends the SELCT_APPLICATION command to the card
    private func SelectApplication() {
        Logger.logDebug("Transmit: SELECT_APPLICATION", category: .nfc)
        do {
            let apdu = try APDUCommand(command: APDU_SELECT)
            Transmit(command: apdu, on_response_event: OnSelectApplicationCompleted)
        } catch {
            Logger.logError("Failed to create SELECT_APPLICATION command", error: error, category: .nfc)
            OnActionCompleted?(false, nil, "Failed to create APDU command: \(error.localizedDescription)", readerSession)
        }
    }
    
    /// Handles the response of the SELECT_APPLICATION command. When successful, it sends the next command to get the key
    /// - Parameter response: Response of SELECT_APPLICATION
    private func OnSelectApplicationCompleted(response: APDUResponse) {
        if(!response.IsSuccessSW()) {
            Logger.logError("Response: SELECT_APPLICATION Failed: \(response.GetSWHex())", category: .nfc)
            OnActionCompleted?(false, nil, "SELECT_APP SW: " + response.GetSWHex(), readerSession)
            return
        }
        Logger.logDebug("Response: SELECT_APPLICATION Success", category: .nfc)
        
        // Application selected, Read the public-key from the card
        GetKeyInfo()
    }
    
    // MARK: - Command handler - GET_KEY_INFO
    /// Frames the GET_KEY_INFO command with the key index
    /// - Returns: GET_KEY_INFO command
    private func GetKeyInfoCommand() -> Data {
        var command = ADPU_GET_KEY_INFO
        command[2] = keyIndex
        return command
    }
    
    /// Sends the GET_KEY_INFO command to the card
    private func GetKeyInfo() {
        Logger.logDebug("Transmit: GET_KEY_INFO", category: .nfc)
        do {
            let apdu = try APDUCommand(command: GetKeyInfoCommand())
            Transmit(command: apdu, on_response_event: OnGetKeyInfoCompleted)
        } catch {
            Logger.logError("Failed to create GET_KEY_INFO command", error: error, category: .nfc)
            OnActionCompleted?(false, nil, "Failed to create APDU command: \(error.localizedDescription)", readerSession)
        }
    }
    
    /// Handles the response of the GET_KEY_INFO command. When successful, completes the action. When failed, it generates the key
    /// - Parameter response: Response of GET_KEY_INFO
    private func OnGetKeyInfoCompleted(response: APDUResponse) {
        if(response.IsSuccessSW()) {
             Logger.logDebug("Response: GET_KEY_INFO Success", category: .nfc)
            
            // Complete the action
            OnActionCompleted?(true, response.data, nil, readerSession)
        }else{
             Logger.logWarning("Response: GET_KEY_INFO Failed: \(response.GetSWHex())", category: .nfc)
            
            // When selected key index is not available, generate new key pair
            if(response.CheckSW(sw: APDUResponse.SW_KEY_WITH_IDX_NOT_AVAILABLE)) {
                GenerateNewSecp256K1Keypair()
            } else {
                OnActionCompleted?(false, nil, "GET_KEY_INFO SW: " + response.GetSWHex(), readerSession)
            }
        }
    }
    
    // MARK: - Command handler - GENERATE_KEY
    /// Sends the GENERATE_KEY command to the card
    private func GenerateNewSecp256K1Keypair() {
        Logger.logDebug("Transmit: GENERATE_KEY", category: .nfc)
        do {
            let apdu = try APDUCommand(command: ADPU_GENERATE_KEY)
            Transmit(command: apdu, on_response_event: OnGenerateNewSecp256K1KeypairCompleted)
        } catch {
            Logger.logError("Failed to create GENERATE_KEY command", error: error, category: .nfc)
            OnActionCompleted?(false, nil, "Failed to create APDU command: \(error.localizedDescription)", readerSession)
        }
    }
    
    /// Handles the response of the GENERATE_KEY command. When failed, it completes the action.
    /// When successful, it checks if the required key-index is available and generates key again if required.
    /// If the required key index is populated, it reads the public key.
    /// - Parameter response: Response of GENERATE_KEY command
    private func OnGenerateNewSecp256K1KeypairCompleted(response: APDUResponse) {
        if(response.IsSuccessSW()) {
            // Response data contains the generated key index
            guard let responseData = response.data, responseData.count == 1 else {
                 Logger.logError("GENERATE_KEY invalid response - Doesn't have generated key index", category: .nfc)
                OnActionCompleted?(false, nil, "Invalid GENERATE_KEY response", readerSession)
                return
            }

            Logger.logDebug("Response: GENERATE_KEY Success", category: .nfc)

            // Newly generated key's index
            let newKeyIndex = responseData[0]
            if(newKeyIndex < keyIndex) {
                Logger.logDebug("Required key index not generated yet. Generating keypair again.", category: .nfc)
                GenerateNewSecp256K1Keypair()
            }
            else {
                Logger.logDebug("Required key index is generated. Reading the public-key.", category: .nfc)
                GetKeyInfo()
            }
        } else {
            Logger.logWarning("Response: GENERATE_KEY Failed: \(response.GetSWHex())", category: .nfc)
            
            if(response.CheckSW(sw: APDUResponse.SW_KEY_STORAGE_FULL)) {
                Logger.logError("Key storage is full", category: .nfc)
                OnActionCompleted?(false, nil, "Key storage is full", readerSession)
            } else {
                OnActionCompleted?(false, nil, "GENERATE_KEY SW: " + response.GetSWHex(), readerSession)
            }
        }
    }
    
    // MARK: - Command handler - GENERATE_SIGNATURE
    /// Triggers the APDU exchanges to generate a signature from the card
    /// - Parameters:
    ///   - keyIndex: Key index to use for signing. Must be >0.
    ///   - messageDigest: 32-byte message digest to sign
    ///   - completion_handler: Handler method to be called when the action is completed
    func generateSignature(keyIndex: UInt8, messageDigest: Data, completion_handler: @escaping (Bool, Data?,String?,NFCTagReaderSession) -> Void) {
        self.keyIndex = keyIndex
        self.messageDigest = messageDigest
        self.OnActionCompleted = completion_handler
        
        // Validate message digest is exactly 32 bytes
        if messageDigest.count != 32 {
            Logger.logError("Message digest must be exactly 32 bytes, got \(messageDigest.count)", category: .nfc)
            OnActionCompleted?(false, nil, "Invalid message digest length: \(messageDigest.count) bytes", readerSession)
            return
        }
        
        SelectApplicationForSignature()
    }
    
    /// Sends the SELECT_APPLICATION command for signature generation
    private func SelectApplicationForSignature() {
        Logger.logDebug("Transmit: SELECT_APPLICATION (for signature)", category: .nfc)
        do {
            let apdu = try APDUCommand(command: APDU_SELECT)
            Transmit(command: apdu, on_response_event: OnSelectApplicationForSignatureCompleted)
        } catch {
            Logger.logError("Failed to create SELECT_APPLICATION command for signature", error: error, category: .nfc)
            OnActionCompleted?(false, nil, "Failed to create APDU command: \(error.localizedDescription)", readerSession)
        }
    }
    
    /// Handles the response of the SELECT_APPLICATION command for signature. When successful, sends GENERATE_SIGNATURE
    /// - Parameter response: Response of SELECT_APPLICATION
    private func OnSelectApplicationForSignatureCompleted(response: APDUResponse) {
        if(!response.IsSuccessSW()) {
            Logger.logError("Response: SELECT_APPLICATION Failed: \(response.GetSWHex())", category: .nfc)
            OnActionCompleted?(false, nil, "SELECT_APP SW: " + response.GetSWHex(), readerSession)
            return
        }
        Logger.logDebug("Response: SELECT_APPLICATION Success", category: .nfc)
        
        // Application selected, generate signature
        GenerateSignature()
    }
    
    /// Frames the GENERATE_SIGNATURE command with the key index and message digest
    /// - Returns: GENERATE_SIGNATURE command
    private func GenerateSignatureCommand() -> Data {
        // APDU format: [0x00, 0x18, keyIndex, 0x00, 0x20] + messageDigest (32 bytes) + [0x00]
        var command = Data()
        command.append(0x00)  // CLA
        command.append(0x18)  // INS (GENERATE_SIGNATURE)
        command.append(keyIndex)  // P1 (key index)
        command.append(0x00)  // P2
        command.append(0x20)  // Lc (32 bytes)

        if let digest = messageDigest {
            command.append(digest)  // Message digest (32 bytes)
        } else {
            Logger.logError("messageDigest is nil in GenerateSignatureCommand", category: .nfc)
            // Append zeros as fallback
            command.append(Data(repeating: 0, count: 32))
        }

        command.append(0x00)  // Le

        return command
    }
    
    /// Sends the GENERATE_SIGNATURE command to the card
    private func GenerateSignature() {
        let command = GenerateSignatureCommand()
        do {
            let apdu = try APDUCommand(command: command)
            Transmit(command: apdu, on_response_event: OnGenerateSignatureCompleted)
        } catch {
            Logger.logError("Failed to create GENERATE_SIGNATURE command", error: error, category: .nfc)
            OnActionCompleted?(false, nil, "Failed to create APDU command: \(error.localizedDescription)", readerSession)
        }
    }
    
    /// Handles the response of the GENERATE_SIGNATURE command
    /// - Parameter response: Response of GENERATE_SIGNATURE
    private func OnGenerateSignatureCompleted(response: APDUResponse) {
        if(response.IsSuccessSW()) {
            // Response format: 4 bytes global counter + 4 bytes key counter + DER signature
            
            // Complete the action with full response
            OnActionCompleted?(true, response.data, nil, readerSession)
        } else {
            Logger.logError("Response: GENERATE_SIGNATURE Failed: \(response.GetSWHex())", category: .nfc)
            OnActionCompleted?(false, nil, "GENERATE_SIGNATURE SW: " + response.GetSWHex(), readerSession)
        }
    }
}
