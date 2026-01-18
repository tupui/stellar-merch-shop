/**
 * Blockchain Service
 * Handles Soroban contract interactions
 */

import Foundation
import stellarsdk
import OSLog

final class BlockchainService {
    private let config = AppConfig.shared

    /// RPC client instance that gets recreated when network changes
    private var rpcClient: SorobanServer
    
    init() {
        self.rpcClient = SorobanServer(endpoint: config.rpcUrl)
        
        // Observe network changes and recreate RPC client
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNetworkChange),
            name: .networkDidChange,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleNetworkChange() {
        self.rpcClient = SorobanServer(endpoint: config.rpcUrl)
        Logger.logDebug("RPC client recreated for network: \(config.currentNetwork.rawValue)", category: .blockchain)
    }
    
    /// Get owner of a token from the contract (read-only, no private key needed)
    /// - Parameters:
    ///   - contractId: Contract ID
    ///   - tokenId: Token ID
    ///   - accountId: Public account address for simulation (starts with 'G')
    /// - Returns: Owner address string
    /// - Throws: AppError if call fails
    func getTokenOwner(contractId: String, tokenId: UInt64, accountId: String) async throws -> String {
        let args: [SCValXDR] = [SCValXDR.u64(tokenId)]
        
        let returnValue = try await BlockchainHelpers.buildAndSimulateReadOnly(
            contractId: contractId,
            method: "owner_of",
            arguments: args,
            accountId: accountId,
            rpcClient: rpcClient
        )
        
        guard case .address(let address) = returnValue else {
            throw AppError.blockchain(.invalidResponse)
        }
        
        guard let ownerAddress = address.accountId else {
            throw AppError.blockchain(.invalidResponse)
        }
        
        return ownerAddress
    }

    /// Get token ID for a given chip public key from the contract (read-only, no private key needed)
    /// - Parameters:
    ///   - contractId: Contract ID
    ///   - publicKey: Chip's public key (65 bytes, uncompressed SEC1 format)
    ///   - accountId: Public account address for simulation (starts with 'G')
    /// - Returns: Token ID
    /// - Throws: AppError if call fails
    func getTokenId(contractId: String, publicKey: Data, accountId: String) async throws -> UInt64 {
        guard publicKey.count == 65 else {
            throw AppError.validation("Invalid public key length: \(publicKey.count), expected 65")
        }
        
        let args: [SCValXDR] = [SCValXDR.bytes(publicKey)]
        
        do {
            let returnValue = try await BlockchainHelpers.buildAndSimulateReadOnly(
                contractId: contractId,
                method: "token_id",
                arguments: args,
                accountId: accountId,
                rpcClient: rpcClient
            )
            
            guard case .u64(let tokenId) = returnValue else {
                throw AppError.blockchain(.invalidResponse)
            }
            
            return tokenId
        } catch {
            // Check for account not found errors
            let errorString = "\(error)"
            let errorLowercased = errorString.lowercased()
            if errorLowercased.contains("could not find account") || 
               errorLowercased.contains("account not found") ||
               errorLowercased.contains("does not exist") {
                throw AppError.wallet(.noWallet)
            }
            
            // Re-throw if already AppError
            if error is AppError {
                throw error
            }
            
            // Check for contract errors
            if let contractError = BlockchainHelpers.extractContractError(from: error) {
                throw contractError
            }
            
            throw AppError.blockchain(.transactionRejected(errorString))
        }
    }

    /// Get token URI for a given token ID from the contract (read-only, no private key needed)
    /// - Parameters:
    ///   - contractId: Contract ID
    ///   - tokenId: Token ID
    ///   - accountId: Public account address for simulation (starts with 'G')
    /// - Returns: Token URI string (IPFS URL)
    /// - Throws: AppError if call fails
    func getTokenUri(contractId: String, tokenId: UInt64, accountId: String) async throws -> String {
        let args: [SCValXDR] = [SCValXDR.u64(tokenId)]
        
        let returnValue = try await BlockchainHelpers.buildAndSimulateReadOnly(
            contractId: contractId,
            method: "token_uri",
            arguments: args,
            accountId: accountId,
            rpcClient: rpcClient
        )
        
        let uri: String
        switch returnValue {
        case .string(let stringValue):
            uri = stringValue
        case .bytes(let bytesValue):
            guard let stringFromBytes = String(data: Data(bytesValue), encoding: .utf8) else {
                throw AppError.blockchain(.invalidResponse)
            }
            uri = stringFromBytes
        default:
            throw AppError.blockchain(.invalidResponse)
        }
        
        // Clean up the URI - remove quotes and null bytes
        var cleanedUri = uri.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        cleanedUri = cleanedUri.trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
        
        return cleanedUri
    }

    /// Get nonce for a public key from the contract (read-only, no private key needed)
    /// - Parameters:
    ///   - contractId: Contract ID
    ///   - publicKey: Public key as Data (65 bytes, uncompressed)
    ///   - accountId: Public account address for simulation (starts with 'G')
    /// - Returns: Current nonce value
    /// - Throws: AppError if call fails (throws instead of returning 0)
    func getNonce(contractId: String, publicKey: Data, accountId: String) async throws -> UInt32 {
        let args: [SCValXDR] = [SCValXDR.bytes(publicKey)]
        
        do {
            let returnValue = try await BlockchainHelpers.buildAndSimulateReadOnly(
                contractId: contractId,
                method: "get_nonce",
                arguments: args,
                accountId: accountId,
                rpcClient: rpcClient
            )
            
            guard case .u32(let nonce) = returnValue else {
                throw AppError.blockchain(.invalidResponse)
            }
            
            return nonce
        } catch {
            // Re-throw if already AppError
            if error is AppError {
                throw error
            }
            
            // Check for contract errors
            if let contractError = BlockchainHelpers.extractContractError(from: error) {
                throw contractError
            }
            
            // For nonce, if it's a "not found" type error, return 0 (first use)
            let errorString = "\(error)"
            let errorLowercased = errorString.lowercased()
            if errorLowercased.contains("not found") || 
               errorLowercased.contains("does not exist") ||
               errorLowercased.contains("no data") {
                return 0
            }
            
            throw AppError.blockchain(.invalidResponse)
        }
    }
    
    /// Contract method type for recovery ID determination
    enum ContractMethod {
        case claim(claimant: String)
        case transfer(from: String, to: String, tokenId: UInt64)
        case mint
    }
    
    /// Determine recovery ID by simulating the appropriate contract call with each recovery ID (0-3)
    /// This is done offline (simulation only, no transaction submission)
    /// Matches JS implementation: determineRecoveryId() in src/util/crypto.ts
    /// - Parameters:
    ///   - contractId: Contract ID
    ///   - method: The contract method being executed (claim, transfer, or mint)
    ///   - message: SEP-53 message (without nonce)
    ///   - signature: ECDSA signature (64 bytes: r + s)
    ///   - publicKey: Chip public key (65 bytes, uncompressed)
    ///   - nonce: Nonce value
    ///   - sourceKeyPair: Source account keypair
    /// - Returns: The correct recovery ID (0-3)
    /// - Throws: AppError if no matching recovery ID found
    func determineRecoveryId(
        contractId: String,
        method: ContractMethod,
        message: Data,
        signature: Data,
        publicKey: Data,
        nonce: UInt32,
        sourceKeyPair: KeyPair
    ) async throws -> UInt32 {
        let recoveryIds: [UInt32] = [0, 1, 2, 3]
        var errors: [String] = []
        
        for recoveryId in recoveryIds {
            
            do {
                // Try to build the transaction (this will simulate it)
                // If simulation succeeds without invalidSignature error, this recovery ID is correct
                // We simulate the SAME method that will actually be called
                switch method {
                case .claim(let claimant):
                    let (_ , _) = try await buildClaimTransaction(
                        contractId: contractId,
                        claimant: claimant,
                        message: message,
                        signature: signature,
                        recoveryId: recoveryId,
                        publicKey: publicKey,
                        nonce: nonce,
                        sourceAccount: sourceKeyPair.accountId,
                        sourceKeyPair: sourceKeyPair
                    )
                case .transfer(let from, let to, let tokenId):
                    let _ = try await buildTransferTransaction(
                        contractId: contractId,
                        from: from,
                        to: to,
                        tokenId: tokenId,
                        message: message,
                        signature: signature,
                        recoveryId: recoveryId,
                        publicKey: publicKey,
                        nonce: nonce,
                        sourceKeyPair: sourceKeyPair
                    )
                case .mint:
                    let (_ , _) = try await buildMintTransaction(
                        contractId: contractId,
                        message: message,
                        signature: signature,
                        recoveryId: recoveryId,
                        publicKey: publicKey,
                        nonce: nonce,
                        sourceKeyPair: sourceKeyPair
                    )
                }
                
                return recoveryId
            } catch {
                if case AppError.blockchain(.contract(.invalidSignature)) = error {
                    let errorMsg = "Recovery ID \(recoveryId): InvalidSignature"
                    errors.append(errorMsg)
                    continue
                }
                
                let errorString = "\(error)"
                if errorString.contains("InvalidInput") ||
                   errorString.contains("recovery failed") ||
                   errorString.contains("recover_key_ecdsa") {
                    let errorMsg = "Recovery ID \(recoveryId): InvalidInput"
                    errors.append(errorMsg)
                    continue
                }
                
                return recoveryId
            }
        }
        
        // If we get here, no recovery ID worked
        if !errors.isEmpty {
            Logger.logError("Failed to determine recovery ID. Errors: \(errors.joined(separator: ", "))", category: .blockchain)
        }
        throw AppError.blockchain(.transactionFailed)
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
    /// - Returns: Tuple with Transaction object (not signed) and the token ID from simulation
    /// - Throws: AppError if building fails
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
    ) async throws -> (transaction: Transaction, tokenId: UInt64) {
        let claimantAddress = try SCAddressXDR(accountId: claimant)
        
        let args: [SCValXDR] = [
            SCValXDR.address(claimantAddress),
            SCValXDR.bytes(message),
            SCValXDR.bytes(signature),
            SCValXDR.u32(recoveryId),
            SCValXDR.bytes(publicKey),
            SCValXDR.u32(nonce)
        ]
        
        let transaction = try await BlockchainHelpers.buildTransaction(
            contractId: contractId,
            method: "claim",
            arguments: args,
            sourceKeyPair: sourceKeyPair
        )
        
        // Extract token ID by simulating the transaction
        var tokenId: UInt64 = 0
        do {
            let returnValue = try await BlockchainHelpers.simulateAndDecode(transaction: transaction, rpcClient: rpcClient)
            if case .u64(let simulatedTokenId) = returnValue {
                tokenId = simulatedTokenId
            }
        } catch {
            // If simulation fails, tokenId remains 0
        }
        
        return (transaction: transaction, tokenId: tokenId)
    }

    /// Build transfer transaction
    /// - Parameters:
    ///   - contractId: Contract ID
    ///   - from: Sender address
    ///   - to: Recipient address
    ///   - tokenId: Token ID to transfer
    ///   - message: SEP-53 message (without nonce)
    ///   - signature: ECDSA signature (64 bytes: r + s)
    ///   - recoveryId: Recovery ID (0-3)
    ///   - publicKey: Chip public key (65 bytes, uncompressed)
    ///   - nonce: Nonce value
    ///   - sourceKeyPair: Source account keypair for signing
    /// - Returns: Transaction object ready for signing
    /// - Throws: AppError if building fails
    func buildTransferTransaction(
        contractId: String,
        from: String,
        to: String,
        tokenId: UInt64,
        message: Data,
        signature: Data,
        recoveryId: UInt32,
        publicKey: Data,
        nonce: UInt32,
        sourceKeyPair: KeyPair
    ) async throws -> Transaction {
        let fromAddress = try SCAddressXDR(accountId: from)
        let toAddress = try SCAddressXDR(accountId: to)

        let args: [SCValXDR] = [
            SCValXDR.address(fromAddress),
            SCValXDR.address(toAddress),
            SCValXDR.u64(tokenId),
            SCValXDR.bytes(message),
            SCValXDR.bytes(signature),
            SCValXDR.u32(recoveryId),
            SCValXDR.bytes(publicKey),
            SCValXDR.u32(nonce)
        ]

        return try await BlockchainHelpers.buildTransaction(
            contractId: contractId,
            method: "transfer",
            arguments: args,
            sourceKeyPair: sourceKeyPair
        )
    }

    /// Build mint transaction
    /// - Parameters:
    ///   - contractId: Contract ID
    ///   - message: SEP-53 message (without nonce)
    ///   - signature: ECDSA signature (64 bytes: r + s)
    ///   - recoveryId: Recovery ID (0-3)
    ///   - publicKey: Chip public key (65 bytes, uncompressed)
    ///   - nonce: Nonce value
    ///   - sourceKeyPair: Source account keypair for signing
    /// - Returns: Tuple with Transaction object and the token ID from simulation
    /// - Throws: AppError if building fails
    func buildMintTransaction(
        contractId: String,
        message: Data,
        signature: Data,
        recoveryId: UInt32,
        publicKey: Data,
        nonce: UInt32,
        sourceKeyPair: KeyPair
    ) async throws -> (transaction: Transaction, tokenId: UInt64) {
        let args: [SCValXDR] = [
            SCValXDR.bytes(message),
            SCValXDR.bytes(signature),
            SCValXDR.u32(recoveryId),
            SCValXDR.bytes(publicKey),
            SCValXDR.u32(nonce)
        ]

        let transaction = try await BlockchainHelpers.buildTransaction(
            contractId: contractId,
            method: "mint",
            arguments: args,
            sourceKeyPair: sourceKeyPair
        )

        // Extract token ID by simulating the transaction
        var tokenId: UInt64 = 0
        do {
            let returnValue = try await BlockchainHelpers.simulateAndDecode(transaction: transaction, rpcClient: rpcClient)
            if case .u64(let simulatedTokenId) = returnValue {
                tokenId = simulatedTokenId
            }
        } catch {
            // If simulation fails, tokenId remains 0
        }

        return (transaction: transaction, tokenId: tokenId)
    }

    /// Submit transaction to network
    /// - Parameters:
    ///   - transaction: Signed transaction object (matching test script pattern)
    ///   - progressCallback: Optional callback for progress updates during polling
    /// - Returns: Transaction hash
    /// - Throws: AppError if submission fails
    func submitTransaction(_ transaction: Transaction, progressCallback: ((String) -> Void)? = nil) async throws -> String {
        guard !transaction.operations.isEmpty else {
            Logger.logError("Transaction has no operations", category: .blockchain)
            throw AppError.blockchain(.transactionFailed)
        }
        
        // Compute transaction hash before sending (needed for polling)
        let hashString = try BlockchainHelpers.getTransactionHash(transaction)
        
        progressCallback?("Sending transaction to blockchain network...")
        let sentTxResponse = await self.rpcClient.sendTransaction(transaction: transaction)
        
        let sentTx: SendTransactionResponse
        switch sentTxResponse {
        case .success(let response):
            sentTx = response
            
            if sentTx.status == "ERROR" {
                Logger.logError("Transaction was immediately rejected with status: ERROR", category: .blockchain)
                if let errorResult = sentTx.errorResult {
                    Logger.logError("Error result code: \(errorResult.code)", category: .blockchain)
                    
                    let errorString = "\(errorResult)"
                    if let contractError = ContractError.fromErrorString(errorString) {
                        Logger.logError("Contract error detected: \(contractError)", category: .blockchain)
                        throw AppError.blockchain(.contract(contractError))
                    }
                    
                    // Handle specific error codes
                    switch errorResult.code {
                    case .malformed:
                        throw AppError.blockchain(.transactionRejected("Transaction was rejected as malformed. Please check your transaction parameters."))
                    case .badAuth:
                        throw AppError.blockchain(.transactionRejected("Transaction authentication failed. Please check your signature."))
                    case .badSeq:
                        throw AppError.blockchain(.transactionRejected("Transaction sequence number is incorrect."))
                    default:
                        throw AppError.blockchain(.transactionRejected("Transaction was rejected: \(errorResult.code)"))
                    }
                } else {
                    throw AppError.blockchain(.transactionRejected("Transaction was rejected by the network."))
                }
            }
            
            if sentTx.status != "PENDING" && sentTx.status != "SUCCESS" {
                if sentTx.status == "SUCCESS" {
                    return hashString
                } else {
                    throw AppError.blockchain(.transactionRejected("Transaction status: \(sentTx.status)"))
                }
            }
        case .failure(let error):
            Logger.logError("Failed to send transaction: \(error)", category: .blockchain)
            
            let errorString = "\(error)"
            let errorLowercased = errorString.lowercased()
            if errorLowercased.contains("could not find account") || 
               errorLowercased.contains("account not found") ||
               errorLowercased.contains("does not exist") ||
               errorLowercased.contains("requestfailed") {
                throw AppError.wallet(.noWallet) // Account doesn't exist on network
            }
            
            // Use structured error parsing
            if let contractError = ContractError.fromErrorString(errorString) {
                Logger.logError("Contract error detected in send response: \(contractError)", category: .blockchain)
                throw AppError.blockchain(.contract(contractError))
            }
            
            throw AppError.blockchain(.transactionRejected("Failed to send transaction: \(error.localizedDescription)"))
        }
        
        progressCallback?("Waiting for blockchain confirmation...")
        let maxAttempts = 30
        let initialDelay: TimeInterval = 2.0
        let pollInterval: TimeInterval = 1.0
        var attempts = 0
        
        while attempts < maxAttempts {
            let delay = attempts == 0 ? initialDelay : pollInterval
            let delayNanoseconds = UInt64(delay * 1_000_000_000)
            progressCallback?("Confirming transaction...")
            try await Task.sleep(nanoseconds: delayNanoseconds)
            
            let txResponseEnum = await self.rpcClient.getTransaction(transactionHash: hashString)
            
            switch txResponseEnum {
            case .success(let txResponse):
                if txResponse.status == GetTransactionResponse.STATUS_SUCCESS {
                    Logger.logInfo("Transaction confirmed successfully!", category: .blockchain)
                    progressCallback?("Transaction confirmed!")
                    return hashString
                } else if txResponse.status == GetTransactionResponse.STATUS_FAILED {
                    Logger.logError("Transaction failed on network", category: .blockchain)
                    
                    let responseString = "\(txResponse)"
                    if let contractError = ContractError.fromErrorString(responseString) {
                        Logger.logError("Contract error detected in transaction response: \(contractError)", category: .blockchain)
                        throw AppError.blockchain(.contract(contractError))
                    }
                    
                    throw AppError.blockchain(.transactionFailed)
                } else {
                    // Transaction still pending, continue polling
                    attempts += 1
                    continue
                }
            case .failure(let error):
                Logger.logWarning("Error getting transaction (attempt \(attempts + 1)/\(maxAttempts)): \(error)", category: .blockchain)
                attempts += 1
                continue
            }
        }
        
        Logger.logWarning("Transaction polling timed out after \(attempts) attempts", category: .blockchain)
        throw AppError.blockchain(.transactionTimeout)
    }
}



