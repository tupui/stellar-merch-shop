/**
 * Wallet Service
 * Manages wallet connections and transaction signing
 */

import Foundation
import stellarsdk

struct WalletConnection {
    let address: String  // Stellar address (public key)
    let name: String
}

class WalletService {
    private let secureKeyStorage = SecureKeyStorage()
    private let addressKey = "wallet_address"
    
    /// Load wallet from secret key
    /// - Parameter secretKey: Stellar secret key (starts with 'S', 56 chars)
    /// - Returns: WalletConnection with address
    /// - Throws: WalletError if key is invalid or storage fails
    func loadWalletFromSecretKey(_ secretKey: String) async throws -> WalletConnection {
        // Validate secret key format
        let trimmedKey = secretKey.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedKey.isEmpty else {
            throw WalletError.invalidSecretKey("Secret key cannot be empty")
        }
        
        guard trimmedKey.hasPrefix("S") else {
            throw WalletError.invalidSecretKey("Invalid secret key format. Stellar secret keys start with 'S'")
        }
        
        guard trimmedKey.count == 56 else {
            throw WalletError.invalidSecretKey("Invalid secret key length. Stellar secret keys are 56 characters")
        }
        
        // Generate KeyPair from secret key
        let keyPair: KeyPair
        do {
            keyPair = try KeyPair(secretSeed: trimmedKey)
        } catch {
            throw WalletError.invalidSecretKey("Failed to create key pair from secret key: \(error.localizedDescription)")
        }
        
        // Get public key/address
        let address = keyPair.accountId
        
        // Store private key in Secure Enclave
        do {
            try secureKeyStorage.storePrivateKey(trimmedKey)
        } catch {
            throw WalletError.keychainError
        }
        
        // Store public info in UserDefaults
        UserDefaults.standard.set(address, forKey: addressKey)
        
        return WalletConnection(
            address: address,
            name: "Manual Key"
        )
    }
    
    /// Get stored wallet info (if any)
    /// - Returns: WalletConnection if wallet is stored, nil otherwise
    func getStoredWallet() -> WalletConnection? {
        guard let address = UserDefaults.standard.string(forKey: addressKey),
              !address.isEmpty else {
            return nil
        }
        
        return WalletConnection(
            address: address,
            name: "Manual Key"
        )
    }
    
    /// Sign a transaction XDR
    /// - Parameter transactionXdr: Transaction XDR as Data
    /// - Returns: Signed transaction XDR as Data
    /// - Throws: WalletError if signing fails
    func signTransaction(_ transactionXdr: Data) async throws -> Data {
        guard let privateKeyString = try secureKeyStorage.loadPrivateKey() else {
            throw WalletError.noWalletConfigured
        }
        
        let keyPair = try KeyPair(secretSeed: privateKeyString)
        let transactionXdrString = transactionXdr.base64EncodedString()
        let stellarTransaction = try Transaction(envelopeXdr: transactionXdrString)
        
        // Determine network
        let network: Network
        switch AppConfig.shared.currentNetwork {
        case .testnet:
            network = .testnet
        case .mainnet:
            network = .public
        }
        
        try stellarTransaction.sign(keyPair: keyPair, network: network)
        
        guard let signedXdr = stellarTransaction.xdrEncoded else {
            throw WalletError.signingFailed
        }
        
        return Data(base64Encoded: signedXdr) ?? Data()
    }
    
    /// Logout - clear stored wallet
    func logout() throws {
        try secureKeyStorage.deletePrivateKey()
        UserDefaults.standard.removeObject(forKey: addressKey)
    }
}

enum WalletError: Error, LocalizedError {
    case invalidSecretKey(String)
    case keychainError
    case noWalletConfigured
    case signingFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidSecretKey(let message):
            return message
        case .keychainError:
            return "Failed to access Keychain"
        case .noWalletConfigured:
            return "No wallet configured"
        case .signingFailed:
            return "Transaction signing failed"
        }
    }
}
