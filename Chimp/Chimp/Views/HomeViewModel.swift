import SwiftUI
import Combine

class HomeViewModel: ObservableObject {
    private let walletService = WalletService()
    
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showingTransferAlert = false
    @Published var showingSignAlert = false
    @Published var showingNFCOperation = false
    @Published var nfcOperationType: NFCOperationView.OperationType?
    @Published var showingNFTView = false
    @Published var loadedNFTContractId: String?
    @Published var loadedNFTTokenId: UInt64?
    
    // Operation coordinator will handle the actual NFC operations
    let nfcCoordinator = NFCOperationCoordinator()
    
    init() {
        setupCoordinatorCallbacks()
    }
    
    private func setupCoordinatorCallbacks() {
        nfcCoordinator.onLoadNFTSuccess = { [weak self] contractId, tokenId in
            DispatchQueue.main.async {
                self?.loadedNFTContractId = contractId
                self?.loadedNFTTokenId = tokenId
                self?.showingNFTView = true
            }
        }
        
        nfcCoordinator.onLoadNFTError = { [weak self] error in
            DispatchQueue.main.async {
                self?.errorMessage = error
            }
        }
    }
    
    func loadNFT() {
        guard walletService.getStoredWallet() != nil else {
            errorMessage = "Please login first"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        nfcCoordinator.loadNFT { [weak self] success, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                if let error = error {
                    self?.errorMessage = error
                }
            }
        }
    }
    
    func claimNFT() {
        guard walletService.getStoredWallet() != nil else {
            errorMessage = "Please login first"
            return
        }
        
        guard !AppConfig.shared.contractId.isEmpty else {
            errorMessage = "Please set the contract ID in Settings"
            return
        }
        
        showingNFCOperation = true
        nfcOperationType = .claimNFT
    }
    
    func transferNFT() {
        guard walletService.getStoredWallet() != nil else {
            errorMessage = "Please login first"
            return
        }
        
        guard !AppConfig.shared.contractId.isEmpty else {
            errorMessage = "Please set the contract ID in Settings"
            return
        }
        
        showingTransferAlert = true
    }
    
    func transferNFT(recipient: String, tokenId: UInt64) {
        showingNFCOperation = true
        nfcOperationType = .transferNFT(recipient: recipient, tokenId: tokenId)
    }
    
    func signMessage() {
        showingSignAlert = true
    }
    
    func signMessage(message: Data) {
        showingNFCOperation = true
        nfcOperationType = .signMessage(message: message)
    }
    
    func mintNFT() {
        guard walletService.getStoredWallet() != nil else {
            errorMessage = "Please login first"
            return
        }
        
        guard !AppConfig.shared.contractId.isEmpty else {
            errorMessage = "Please set the contract ID in Settings"
            return
        }
        
        guard AppConfig.shared.isAdminMode else {
            errorMessage = "Admin mode required for minting"
            return
        }
        
        showingNFCOperation = true
        nfcOperationType = .mintNFT
    }
}

