/**
 * Crypto Utilities
 * Provides SEP-53 message creation and signature normalization
 */

import Foundation
import CryptoKit

class CryptoUtils {
    /// Create SEP-53 compliant auth message
    /// - Parameters:
    ///   - contractId: Contract ID (hex string, 32 bytes)
    ///   - functionName: Function name to call
    ///   - args: Function arguments (will be JSON encoded)
    ///   - nonce: Nonce value
    ///   - networkPassphrase: Network passphrase
    /// - Returns: Tuple of (message: Data, messageHash: Data)
    static func createSEP53Message(
        contractId: String,
        functionName: String,
        args: [Any],
        nonce: UInt32,
        networkPassphrase: String
    ) throws -> (message: Data, messageHash: Data) {
        var parts: [Data] = []
        
        // Network passphrase hash (32 bytes)
        let networkData = networkPassphrase.data(using: .utf8) ?? Data()
        let networkHash = Data(SHA256.hash(data: networkData))
        parts.append(networkHash)
        
        // Contract ID (32 bytes)
        guard let contractIdData = Data(hexString: contractId) else {
            throw CryptoError.invalidContractId
        }
        guard contractIdData.count == 32 else {
            throw CryptoError.invalidContractId
        }
        parts.append(contractIdData)
        
        // Function name
        guard let functionNameData = functionName.data(using: .utf8) else {
            throw CryptoError.invalidFunctionName
        }
        parts.append(functionNameData)
        
        // Args (JSON encoded)
        let argsJson = try JSONSerialization.data(withJSONObject: args)
        parts.append(argsJson)
        
        // Concatenate all parts (without nonce)
        var message = Data()
        for part in parts {
            message.append(part)
        }
        
        // Append nonce XDR format
        // ScVal U32: 4 bytes discriminant (3) + 4 bytes value (big-endian)
        var nonceXdr = Data()
        nonceXdr.append(contentsOf: [0x00, 0x00, 0x00, 0x03]) // U32 discriminant
        let nonceBytes = withUnsafeBytes(of: nonce.bigEndian) { Data($0) }
        nonceXdr.append(nonceBytes)
        
        // Message with nonce for hashing
        var messageWithNonce = message
        messageWithNonce.append(nonceXdr)
        
        // Hash the message with nonce
        let messageHash = Data(SHA256.hash(data: messageWithNonce))
        
        return (message: message, messageHash: messageHash)
    }
    
    /// Normalize the S value of an ECDSA signature
    /// Soroban's secp256k1_recover requires normalized S values
    /// - Parameter s: S value as 32-byte Data (big-endian)
    /// - Returns: Normalized S value (32 bytes, big-endian)
    static func normalizeS(_ s: Data) -> Data {
        guard s.count == 32 else {
            return s
        }
        
        // secp256k1 curve order n (big-endian)
        let curveOrder: [UInt8] = [
            0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
            0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFE,
            0xBA, 0xAE, 0xDC, 0xE6, 0xAF, 0x48, 0xA0, 0x3B,
            0xBF, 0xD2, 0x5E, 0x8C, 0xD0, 0x36, 0x41, 0x41
        ]
        
        // Half order = n / 2
        let halfOrder: [UInt8] = [
            0x7F, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
            0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
            0x5D, 0x57, 0x6E, 0x73, 0x57, 0xA4, 0x50, 0x1D,
            0xDF, 0xE9, 0x2F, 0x46, 0x68, 0x1B, 0x20, 0xA0
        ]
        
        // Compare s with halfOrder (big-endian)
        var sGreaterThanHalf = false
        for i in 0..<32 {
            if s[i] > halfOrder[i] {
                sGreaterThanHalf = true
                break
            } else if s[i] < halfOrder[i] {
                break
            }
        }
        
        // If s > halfOrder, normalize: s = n - s
        if sGreaterThanHalf {
            var normalized = Data(count: 32)
            var borrow: UInt8 = 0
            
            for i in (0..<32).reversed() {
                var diff = Int(curveOrder[i]) - Int(s[i]) - Int(borrow)
                if diff < 0 {
                    diff += 256
                    borrow = 1
                } else {
                    borrow = 0
                }
                normalized[i] = UInt8(diff)
            }
            
            return normalized
        }
        
        // s is already normalized
        return s
    }
}

enum CryptoError: Error, LocalizedError {
    case invalidContractId
    case invalidFunctionName
    
    var errorDescription: String? {
        switch self {
        case .invalidContractId:
            return "Invalid contract ID format"
        case .invalidFunctionName:
            return "Invalid function name"
        }
    }
}
