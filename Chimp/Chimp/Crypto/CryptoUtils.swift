/**
 * Crypto Utilities
 * Provides SEP-53 message creation, signature normalization, and DER signature parsing
 */

import Foundation
import CryptoKit
import stellarsdk

// MARK: - Signature Components

struct SignatureComponents {
    let r: Data  // 32 bytes
    let s: Data  // 32 bytes
}

// MARK: - Crypto Utilities

final class CryptoUtils {
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
        // Stellar contract IDs are base32 encoded addresses (56 chars starting with 'C')
        // For SEP-53, we need the raw 32-byte contract ID
        // Format: version (1 byte) + contract ID (32 bytes) + checksum (2 bytes) = 35 bytes
        let contractIdData: Data
        if contractId.hasPrefix("C") && contractId.count == 56 {
            // Stellar contract address - decode from base32 to get 32-byte contract ID
            contractIdData = try decodeStellarContractId(contractId)
        } else if contractId.count == 64, let hexData = Data(hexString: contractId), hexData.count == 32 {
            // Hex string format (64 hex chars = 32 bytes)
            contractIdData = hexData
        } else {
            throw AppError.crypto(.invalidKey("Invalid contract ID format"))
        }
        parts.append(contractIdData)
        
        // Function name
        guard let functionNameData = functionName.data(using: .utf8) else {
            throw AppError.crypto(.invalidOperation("Invalid function name"))
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
        nonceXdr.append(contentsOf: [0x00, 0x00, 0x00, 0x03]) // U32 discriminant (big-endian uint32: 3)
        // Append nonce value as big-endian bytes (4 bytes)
        let nonceByte1 = UInt8((nonce >> 24) & 0xFF)
        let nonceByte2 = UInt8((nonce >> 16) & 0xFF)
        let nonceByte3 = UInt8((nonce >> 8) & 0xFF)
        let nonceByte4 = UInt8(nonce & 0xFF)
        nonceXdr.append(contentsOf: [nonceByte1, nonceByte2, nonceByte3, nonceByte4])
        
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
            0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
            0x5D, 0x57, 0x6E, 0x73, 0x57, 0xA4, 0x50, 0x1D
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
            var borrow = 0
            
            for i in (0..<32).reversed() {
                var diff = Int(curveOrder[i]) - Int(s[i]) - borrow
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
    
    /// Decode Stellar contract ID from base32 address format
    /// Contract addresses are 56 characters starting with 'C'
    /// Returns the 32-byte contract ID for SEP-53 message format
    /// Format: version (1 byte) + contract ID (32 bytes) + checksum (2 bytes) = 35 bytes
    /// Note: This is needed because SEP-53 requires the raw 32-byte contract ID, not the address format
    private static func decodeStellarContractId(_ contractAddress: String) throws -> Data {
        // Stellar uses RFC 4648 base32 alphabet
        let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        var decoded = Data()
        var buffer: UInt64 = 0
        var bits = 0
        
        for char in contractAddress.uppercased() {
            guard let pos = alphabet.firstIndex(of: char) else {
                throw AppError.crypto(.invalidKey("Invalid contract ID format"))
            }
            let value = alphabet.distance(from: alphabet.startIndex, to: pos)
            
            buffer = (buffer << 5) | UInt64(value)
            bits += 5
            
            while bits >= 8 {
                decoded.append(UInt8((buffer >> (bits - 8)) & 0xFF))
                bits -= 8
            }
        }
        
        // Extract 32-byte contract ID (skip version byte, take next 32 bytes, skip checksum)
        guard decoded.count >= 35 else {
            throw AppError.crypto(.invalidKey("Invalid contract ID format"))
        }
        
        return decoded.subdata(in: 1..<33)
    }
}

// MARK: - DER Signature Parser

/// Parses DER-encoded ECDSA signatures from NFC chip
final class DERSignatureParser {
    /// Parse DER-encoded signature to extract r and s components
    /// - Parameter derSignature: DER-encoded signature as Data
    /// - Returns: SignatureComponents with r and s (32 bytes each)
    /// - Throws: AppError if parsing fails
    static func parse(_ derSignature: Data) throws -> SignatureComponents {
        // DER structure: 0x30 || length || 0x02 || r_length || r || 0x02 || s_length || s
        guard derSignature.count >= 8 else {
            throw AppError.derSignature(.parseFailed("Invalid signature length"))
        }
        
        var offset = 0
        
        // Check for 0x30 (SEQUENCE tag)
        guard derSignature[offset] == 0x30 else {
            throw AppError.derSignature(.invalidFormat)
        }
        offset += 1
        
        // Read sequence length
        _ = try readLength(derSignature, offset: &offset)
        
        // Check for 0x02 (INTEGER tag for r)
        guard offset < derSignature.count && derSignature[offset] == 0x02 else {
            throw AppError.derSignature(.invalidComponents)
        }
        offset += 1
        
        // Read r length and value
        let rLength = try readLength(derSignature, offset: &offset)
        guard offset + rLength <= derSignature.count else {
            throw AppError.derSignature(.invalidComponents)
        }
        
        var r = derSignature.subdata(in: offset..<(offset + rLength))
        offset += rLength
        
        // Remove leading zero if present (DER encoding may add padding)
        if r.count > 32 && r[0] == 0x00 {
            r = r.subdata(in: 1..<r.count)
        }
        
        // Pad to 32 bytes if needed
        if r.count < 32 {
            let padding = Data(repeating: 0, count: 32 - r.count)
            r = padding + r
        } else if r.count > 32 {
            // Truncate if somehow longer
            r = r.prefix(32)
        }
        
        // Check for 0x02 (INTEGER tag for s)
        guard offset < derSignature.count && derSignature[offset] == 0x02 else {
            throw AppError.derSignature(.invalidComponents)
        }
        offset += 1
        
        // Read s length and value
        let sLength = try readLength(derSignature, offset: &offset)
        guard offset + sLength <= derSignature.count else {
            throw AppError.derSignature(.invalidComponents)
        }
        
        var s = derSignature.subdata(in: offset..<(offset + sLength))
        offset += sLength
        
        // Remove leading zero if present
        if s.count > 32 && s[0] == 0x00 {
            s = s.subdata(in: 1..<s.count)
        }
        
        // Pad to 32 bytes if needed
        if s.count < 32 {
            let padding = Data(repeating: 0, count: 32 - s.count)
            s = padding + s
        } else if s.count > 32 {
            s = s.prefix(32)
        }
        
        return SignatureComponents(r: r, s: s)
    }
    
    /// Read DER length field
    private static func readLength(_ data: Data, offset: inout Int) throws -> Int {
        guard offset < data.count else {
            throw AppError.derSignature(.invalidFormat)
        }
        
        let firstByte = data[offset]
        offset += 1
        
        if firstByte & 0x80 == 0 {
            // Short form: length is in the byte itself
            return Int(firstByte)
        } else {
            // Long form: number of bytes following indicates length
            let lengthOfLength = Int(firstByte & 0x7F)
            guard lengthOfLength > 0 && lengthOfLength <= 4 else {
                throw AppError.derSignature(.invalidFormat)
            }
            
            guard offset + lengthOfLength <= data.count else {
                throw AppError.derSignature(.invalidFormat)
            }
            
            var length = 0
            for _ in 0..<lengthOfLength {
                length = (length << 8) | Int(data[offset])
                offset += 1
            }
            
            return length
        }
    }
}
