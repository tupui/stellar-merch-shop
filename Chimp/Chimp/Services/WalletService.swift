/**
 * Wallet Service
 * Manages wallet connections and transaction signing
 */

import Foundation
import stellarsdk
import OSLog

struct WalletConnection {
    let address: String  // Stellar address (public key)
    let name: String
}

final class WalletService {
    static let shared = WalletService()
    
    private let secureKeyStorage = SecureKeyStorage()
    private let addressKey = "wallet_address"
    
    /// Load wallet from secret key
    /// - Parameter secretKey: Stellar secret key (starts with 'S', 56 chars)
    /// - Returns: WalletConnection with address
    /// - Throws: AppError if key is invalid or storage fails
    func loadWalletFromSecretKey(_ secretKey: String) async throws -> WalletConnection {
        let trimmedKey = secretKey.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedKey.isEmpty else {
            throw AppError.validation("Secret key cannot be empty")
        }
        
        guard trimmedKey.hasPrefix("S") else {
            throw AppError.validation("Invalid secret key format. Stellar secret keys start with 'S'")
        }
        
        guard trimmedKey.count == 56 else {
            throw AppError.validation("Invalid secret key length. Stellar secret keys are 56 characters")
        }
        
        let keyPair: KeyPair
        do {
            keyPair = try KeyPair(secretSeed: trimmedKey)
        } catch {
            throw AppError.validation("Failed to create key pair from secret key: \(error.localizedDescription)")
        }
        
        let address = keyPair.accountId
        
        do {
            try secureKeyStorage.storePrivateKey(trimmedKey)
            UserDefaults.standard.set(address, forKey: addressKey)
        } catch {
            UserDefaults.standard.removeObject(forKey: addressKey)
            throw AppError.secureStorage(.storageFailed("Failed to store wallet securely"))
        }
        
        return WalletConnection(
            address: address,
            name: "Manual Key"
        )
    }
    
    /// Get stored wallet info (if any)
    /// - Returns: WalletConnection if wallet is stored, nil otherwise
    func getStoredWallet() -> WalletConnection? {
        guard secureKeyStorage.hasStoredKey() else {
            UserDefaults.standard.removeObject(forKey: addressKey)
            return nil
        }
        
        guard let address = UserDefaults.standard.string(forKey: addressKey),
              !address.isEmpty else {
            return nil
        }
        
        return WalletConnection(
            address: address,
            name: "Manual Key"
        )
    }
    
    /// Sign a transaction (modifies the transaction object in place)
    /// - Parameter transaction: Transaction object to sign (will be modified)
    /// - Throws: AppError if signing fails
    func signTransaction(_ transaction: Transaction) async throws {
        let keyPair = try secureKeyStorage.withPrivateKey(reason: "Authenticate to sign the transaction", work: { key in
            try KeyPair(secretSeed: key)
        })
        
        guard !transaction.operations.isEmpty else {
            Logger.logError("Transaction has no operations", category: .blockchain)
            throw AppError.wallet(.signingFailed("Transaction signing failed"))
        }
        
        let network: Network
        switch AppConfig.shared.currentNetwork {
        case .testnet:
            network = .testnet
        case .mainnet:
            network = .public
        }
        
        try transaction.sign(keyPair: keyPair, network: network)
    }
    
    /// Logout - clear stored wallet
    func logout() throws {
        try secureKeyStorage.deletePrivateKey()
        UserDefaults.standard.removeObject(forKey: addressKey)
    }
}

