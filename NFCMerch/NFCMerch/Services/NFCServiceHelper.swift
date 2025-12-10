import Foundation

/// Shared NFC operations for chip-based functions
class NFCServiceHelper {
    
    /// Read public key from NFC chip
    static func readChipPublicKey(nfcService: NFCService) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            nfcService.readPublicKey { result in
                switch result {
                case .success(let publicKey):
                    continuation.resume(returning: publicKey)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Sign message hash with NFC chip
    static func signWithChip(
        nfcService: NFCService,
        messageHash: Data
    ) async throws -> (signatureBytes: Data, recoveryId: UInt8) {
        return try await withCheckedThrowingContinuation { continuation in
            nfcService.signMessage(messageHash: messageHash) { result in
                switch result {
                case .success(let (r, s, recoveryId)):
                    let rBytes = hexToBytes(r)
                    let sBytes = hexToBytes(s)
                    
                    var signatureBytes = Data()
                    signatureBytes.append(rBytes)
                    signatureBytes.append(sBytes)
                    
                    guard signatureBytes.count == 64 else {
                        struct InvalidSignatureError: Error {}
                        continuation.resume(throwing: InvalidSignatureError())
                        return
                    }
                    
                    continuation.resume(returning: (
                        signatureBytes: signatureBytes,
                        recoveryId: UInt8(recoveryId)
                    ))
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

