/**
 * Blockchain Service
 * Handles Soroban contract interactions
 */

import Foundation
import stellarsdk

class BlockchainService {
    private let config = AppConfig.shared
    
    /// Get nonce for a public key from the contract
    /// - Parameters:
    ///   - contractId: Contract ID
    ///   - publicKey: Public key as Data (65 bytes, uncompressed)
    ///   - sourceKeyPair: Source account keypair (must exist on network)
    /// - Returns: Current nonce value, or 0 if not found
    /// - Throws: BlockchainError if call fails
    func getNonce(contractId: String, publicKey: Data, sourceKeyPair: KeyPair) async throws -> UInt32 {
        print("BlockchainService: getNonce called")
        print("BlockchainService: RPC URL: \(config.rpcUrl)")
        print("BlockchainService: Contract ID: \(contractId)")
        print("BlockchainService: Network: \(config.currentNetwork)")
        print("BlockchainService: Public key length: \(publicKey.count)")
        print("BlockchainService: Source account: \(sourceKeyPair.accountId)")
        
        let rpcClient = SorobanServer(endpoint: config.rpcUrl)
        
        // Build the contract call
        let network: Network
        switch config.currentNetwork {
        case .testnet:
            network = .testnet
        case .mainnet:
            network = .public
        }
        
        // Use the actual source account keypair (must exist on network)
        let clientOptions = ClientOptions(
            sourceAccountKeyPair: sourceKeyPair,
            contractId: contractId,
            network: network,
            rpcUrl: config.rpcUrl
        )
        
        let args: [SCValXDR] = [
            SCValXDR.bytes(publicKey)
        ]
        
        let assembledOptions = AssembledTransactionOptions(
            clientOptions: clientOptions,
            methodOptions: MethodOptions(),
            method: "get_nonce",
            arguments: args
        )
        
        // Build and simulate the transaction
        print("BlockchainService: Building transaction...")
        let assembledTx = try await AssembledTransaction.build(options: assembledOptions)
        
        guard let rawTx = assembledTx.raw else {
            print("BlockchainService: ERROR: No raw transaction")
            return 0
        }
        
        print("BlockchainService: Simulating transaction...")
        let simulateRequest = SimulateTransactionRequest(transaction: rawTx)
        let simulateResponse = await rpcClient.simulateTransaction(simulateTxRequest: simulateRequest)
        
        switch simulateResponse {
        case .success(let simulateResult):
            print("BlockchainService: Simulation successful")
            guard let xdrString = simulateResult.results?.first?.xdr,
                  let xdrData = Data(base64Encoded: xdrString),
                  let returnValue = try? XDRDecoder.decode(SCValXDR.self, data: xdrData),
                  case .u32(let nonce) = returnValue else {
                print("BlockchainService: No nonce found in response, defaulting to 0")
                return 0
            }
            print("BlockchainService: Nonce retrieved: \(nonce)")
            return nonce
        case .failure(let error):
            print("BlockchainService: Simulation failed: \(error)")
            // If simulation fails, return 0 (first use)
            return 0
        }
    }
    
    /// Build claim transaction
    /// - Parameters:
    ///   - contractId: Contract ID
    ///   - claimant: Claimant address
    ///   - message: SEP-53 message (without nonce)
    ///   - signature: ECDSA signature (64 bytes: r + s)
    ///   - recoveryId: Recovery ID (0-3)
    ///   - publicKey: Chip public key (65 bytes, uncompressed)
    ///   - nonce: Nonce value
    ///   - sourceAccount: Source account address
    ///   - sourceKeyPair: Source account keypair for signing
    /// - Returns: Transaction XDR as Data
    /// - Throws: BlockchainError if building fails
    func buildClaimTransaction(
        contractId: String,
        claimant: String,
        message: Data,
        signature: Data,
        recoveryId: UInt32,
        publicKey: Data,
        nonce: UInt32,
        sourceAccount: String,
        sourceKeyPair: KeyPair
    ) async throws -> Data {
        print("BlockchainService: buildClaimTransaction called")
        print("BlockchainService: Contract ID: \(contractId)")
        print("BlockchainService: Claimant: \(claimant)")
        print("BlockchainService: Message length: \(message.count)")
        print("BlockchainService: Signature length: \(signature.count)")
        print("BlockchainService: Recovery ID: \(recoveryId)")
        print("BlockchainService: Public key length: \(publicKey.count)")
        print("BlockchainService: Nonce: \(nonce)")
        
        // Create SCValXDR arguments
        let claimantAddress = try SCAddressXDR(accountId: claimant)
        
        let args: [SCValXDR] = [
            SCValXDR.address(claimantAddress),
            SCValXDR.bytes(message),
            SCValXDR.bytes(signature),
            SCValXDR.u32(recoveryId),
            SCValXDR.bytes(publicKey),
            SCValXDR.u32(nonce)
        ]
        
        // Create client options
        let network: Network
        switch config.currentNetwork {
        case .testnet:
            network = .testnet
        case .mainnet:
            network = .public
        }
        
        print("BlockchainService: Network: \(network)")
        print("BlockchainService: RPC URL: \(config.rpcUrl)")
        
        let clientOptions = ClientOptions(
            sourceAccountKeyPair: sourceKeyPair,
            contractId: contractId,
            network: network,
            rpcUrl: config.rpcUrl
        )
        
        // Create assembled transaction options
        let assembledOptions = AssembledTransactionOptions(
            clientOptions: clientOptions,
            methodOptions: MethodOptions(),
            method: "claim",
            arguments: args
        )
        
        // Build the transaction
        print("BlockchainService: Building claim transaction...")
        do {
            let assembledTx = try await AssembledTransaction.build(options: assembledOptions)
            
            // Get the transaction XDR
            guard let rawTx = assembledTx.raw,
                  let xdrString = rawTx.xdrEncoded else {
                print("BlockchainService: ERROR: Failed to get XDR from transaction")
                throw BlockchainError.transactionFailed
            }
            
            print("BlockchainService: Transaction built successfully")
            return Data(base64Encoded: xdrString) ?? Data()
        } catch {
            print("BlockchainService: ERROR building transaction: \(error)")
            if let sorobanError = error as? SorobanRpcRequestError {
                print("BlockchainService: SorobanRpcRequestError code: \(sorobanError)")
            }
            throw error
        }
    }
    
    /// Submit transaction to network
    /// - Parameter transactionXdr: Signed transaction XDR
    /// - Returns: Transaction hash
    /// - Throws: BlockchainError if submission fails
    func submitTransaction(_ transactionXdr: Data) async throws -> String {
        print("BlockchainService: submitTransaction called")
        print("BlockchainService: RPC URL: \(config.rpcUrl)")
        
        let rpcClient = SorobanServer(endpoint: config.rpcUrl)
        
        // Convert XDR Data to Transaction object
        let transactionXdrString = transactionXdr.base64EncodedString()
        print("BlockchainService: Transaction XDR length: \(transactionXdrString.count)")
        
        let stellarTransaction = try Transaction(envelopeXdr: transactionXdrString)
        
        // Compute transaction hash before sending (needed for polling)
        let network: Network
        switch config.currentNetwork {
        case .testnet:
            network = .testnet
        case .mainnet:
            network = .public
        }
        let hashString = try stellarTransaction.getTransactionHash(network: network)
        print("BlockchainService: Transaction hash: \(hashString)")
        
        print("BlockchainService: Sending transaction to RPC...")
        let sentTxResponse = await rpcClient.sendTransaction(transaction: stellarTransaction)
        
        switch sentTxResponse {
        case .success(let sentTx):
            print("BlockchainService: Transaction sent successfully")
            print("BlockchainService: SentTx: \(sentTx)")
        case .failure(let error):
            print("BlockchainService: ERROR sending transaction: \(error)")
            if let sorobanError = error as? SorobanRpcRequestError {
                print("BlockchainService: SorobanRpcRequestError details: \(sorobanError)")
            }
            throw BlockchainError.transactionRejected
        }
        
        // Poll for transaction confirmation
        print("BlockchainService: Polling for transaction confirmation...")
        let maxAttempts = 10
        var attempts = 0
        
        while attempts < maxAttempts {
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            
            let txResponseEnum = await rpcClient.getTransaction(transactionHash: hashString)
            
            switch txResponseEnum {
            case .success(let txResponse):
                print("BlockchainService: Transaction status: \(txResponse.status)")
                if txResponse.status == GetTransactionResponse.STATUS_SUCCESS {
                    print("BlockchainService: Transaction confirmed successfully!")
                    return hashString
                } else if txResponse.status == GetTransactionResponse.STATUS_FAILED {
                    print("BlockchainService: Transaction failed on network")
                    throw BlockchainError.transactionFailed
                } else {
                    attempts += 1
                    continue
                }
            case .failure(let error):
                print("BlockchainService: Error getting transaction (attempt \(attempts + 1)/\(maxAttempts)): \(error)")
                attempts += 1
                continue
            }
        }
        
        print("BlockchainService: Transaction polling timed out")
        throw BlockchainError.transactionTimeout
    }
}

enum BlockchainError: Error, LocalizedError {
    case transactionRejected
    case transactionFailed
    case transactionTimeout
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .transactionRejected:
            return "Transaction was rejected by the network"
        case .transactionFailed:
            return "Transaction failed on the network"
        case .transactionTimeout:
            return "Transaction submission timed out"
        case .invalidResponse:
            return "Invalid response from network"
        }
    }
}
