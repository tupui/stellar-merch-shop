/**
 * Configuration Constants
 * Network and contract configuration for testnet
 */

import Foundation

struct NFCConfig {
    /// Recovery ID for Infineon SECORA chips (hardcoded to 1)
    static let recoveryId: UInt8 = 1
    
    /// Network configuration
    enum Network {
        case testnet
        case mainnet
        case futurenet
        
        var passphrase: String {
            switch self {
            case .testnet:
                return "Test SDF Network ; September 2015"
            case .mainnet:
                return "Public Global Stellar Network ; September 2015"
            case .futurenet:
                return "Test SDF Future Network ; October 2022"
            }
        }
        
        var horizonUrl: String {
            switch self {
            case .testnet:
                return "https://horizon-testnet.stellar.org"
            case .mainnet:
                return "https://horizon.stellar.org"
            case .futurenet:
                return "https://horizon-futurenet.stellar.org"
            }
        }
        
        var rpcUrl: String {
            switch self {
            case .testnet:
                return "https://soroban-testnet.stellar.org"
            case .mainnet:
                return "https://soroban-rpc.mainnet.stellar.org"
            case .futurenet:
                return "https://rpc-futurenet.stellar.org"
            }
        }
    }
    
    /// Current network (default: testnet)
    static var currentNetwork: Network = .testnet
    
    /// Network passphrase
    static var networkPassphrase: String {
        return currentNetwork.passphrase
    }
    
    /// Horizon URL
    static var horizonUrl: String {
        return currentNetwork.horizonUrl
    }
    
    /// RPC URL
    static var rpcUrl: String {
        return currentNetwork.rpcUrl
    }
    
    /// Contract ID - reads from Info.plist based on current network
    /// Can be overridden via UserDefaults for runtime changes
    static var contractId: String {
        // Check UserDefaults first (allows runtime override)
        if let stored = UserDefaults.standard.string(forKey: "contract_id"), !stored.isEmpty {
            return stored
        }
        
        // Read from Info.plist based on current network
        let plistKey: String
        switch currentNetwork {
        case .testnet:
            plistKey = "StellarContractIdTestnet"
        case .mainnet:
            plistKey = "StellarContractIdMainnet"
        case .futurenet:
            // Futurenet uses testnet contract ID as fallback
            plistKey = "StellarContractIdTestnet"
        }
        
        if let contractId = Bundle.main.object(forInfoDictionaryKey: plistKey) as? String,
           !contractId.isEmpty {
            return contractId
        }
        
        // Fallback defaults if Info.plist is not configured
        switch currentNetwork {
        case .testnet:
            return "CD5GYISJJKTE5SMZHS4UVSBXM2A2DKUUOUHAK2SZ24IU5TOBRV54CPK3"
        case .mainnet:
            return ""
        case .futurenet:
            return "CD5GYISJJKTE5SMZHS4UVSBXM2A2DKUUOUHAK2SZ24IU5TOBRV54CPK3"
        }
    }
    
    /// Set contract ID (runtime override via UserDefaults)
    static func setContractId(_ id: String) {
        UserDefaults.standard.set(id, forKey: "contract_id")
    }
    
    /// Get contract ID for a specific network
    static func contractId(for network: Network) -> String {
        let originalNetwork = currentNetwork
        currentNetwork = network
        let id = contractId
        currentNetwork = originalNetwork
        return id
    }
}

