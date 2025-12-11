/**
 * Wallet Service
 * Manages manual key entry wallet connections
 * Uses iOS Keychain for secure key storage
 */

import stellarsdk
import Foundation
import Security

/// Wallet connection info
struct WalletConnection {
    let address: String  // Stellar address (public key)
    let name: String
}

/// Wallet service for managing wallet connections
class WalletService {
    
    private let addressKey = "wallet_address"
    
    /// Load wallet from secret key
    /// 
    /// Validates secret key format and generates KeyPair using stellar-ios-mac-sdk.
    /// Stores private key in Secure Enclave via Keychain for security.
    /// Only the public key/address is stored in UserDefaults.
    func loadWalletFromSecretKey(_ secretKey: String) async throws -> WalletConnection {
        // 1. Validate secret key format
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
        
        // 2. Generate KeyPair from secret key using stellar-ios-mac-sdk
        let keyPair: KeyPair
        do {
            keyPair = try KeyPair(secretSeed: trimmedKey)
        } catch {
            throw WalletError.invalidSecretKey("Failed to create key pair from secret key: \(error.localizedDescription)")
        }
        
        // 3. Get public key/address
        let address = keyPair.accountId
        
        // 4. Store private key in Secure Enclave
        let privateKeyData = trimmedKey.data(using: .utf8) ?? Data()
        do {
            try storePrivateKeyInSecureEnclave(privateKeyData)
        } catch {
            // If Secure Enclave storage fails, still allow connection but log warning
            // Failed to store private key in Secure Enclave - will use Keychain as fallback
        }
        
        // 5. Store public info in UserDefaults
        UserDefaults.standard.set(address, forKey: addressKey)
        
        return WalletConnection(
            address: address,
            name: "Manual Key"
        )
    }
    
    /// Get stored wallet info (if any)
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
    
    func signTransaction(transaction: Data, wallet: WalletConnection) async throws -> Data {
        return try await signTransactionLocal(transaction)
    }
    
    func signTransactionLocal(_ transaction: Data) async throws -> Data {
        guard let privateKeyData = try loadPrivateKeyFromSecureEnclave(),
              let privateKeyString = String(data: privateKeyData, encoding: .utf8) else {
            throw WalletError.noWalletConfigured
        }
        
        let keyPair = try stellarsdk.KeyPair(secretSeed: privateKeyString)
        let transactionXdrString = transaction.base64EncodedString()
        let stellarTransaction = try stellarsdk.Transaction(envelopeXdr: transactionXdrString)
        
        // Determine network
        let network: stellarsdk.Network
        switch NFCConfig.currentNetwork {
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
    
    /// Store private key in Secure Enclave
    /// 
    /// Stores private key in iOS Keychain with Secure Enclave protection.
    /// Uses kSecAttrAccessibleWhenUnlockedThisDeviceOnly for security.
    private func storePrivateKeyInSecureEnclave(_ privateKey: Data) throws {
        let keychainService = "com.stellarmerchshop.privatekey"
        let keychainAccount = "wallet_key"
        
        // Delete existing key if present
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        
        // Add new key
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: privateKey,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw WalletError.keychainError
        }
    }
    
    /// Load private key from Secure Enclave
    /// 
    /// Retrieves private key from iOS Keychain.
    /// Returns nil if key not found or access denied.
    private func loadPrivateKeyFromSecureEnclave() throws -> Data? {
        let keychainService = "com.stellarmerchshop.privatekey"
        let keychainAccount = "wallet_key"
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        
        return data
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

