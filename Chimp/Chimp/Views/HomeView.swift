import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    
    private let walletService = WalletService()
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background with subtle pattern
                Color.chimpBackground
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        headerSection
                        
                        // Error message
                        if let error = viewModel.errorMessage {
                            Text(error)
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(.red)
                                .padding(.horizontal, 20)
                        }
                        
                        // Main action cards
                        actionCardsSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("Chimp")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $viewModel.showingNFCOperation) {
                if let operationType = viewModel.nfcOperationType {
                    NFCOperationView(
                        operationType: operationType,
                        isPresented: $viewModel.showingNFCOperation
                    )
                }
            }
            .sheet(isPresented: $viewModel.showingNFTView) {
                if let contractId = viewModel.loadedNFTContractId,
                   let tokenId = viewModel.loadedNFTTokenId {
                    NavigationView {
                        NFTLoadingView(
                            contractId: contractId,
                            tokenId: tokenId,
                            isPresented: $viewModel.showingNFTView
                        )
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Close") {
                                    viewModel.showingNFTView = false
                                }
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $viewModel.showingTransferAlert) {
                TransferInputView(isPresented: $viewModel.showingTransferAlert) { recipient, tokenId in
                    viewModel.transferNFT(recipient: recipient, tokenId: tokenId)
                }
            }
            .sheet(isPresented: $viewModel.showingSignAlert) {
                SignMessageInputView(isPresented: $viewModel.showingSignAlert) { message in
                    viewModel.signMessage(message: message)
                }
            }
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            // Monkey icon placeholder - you can add your pixel art here
            Image(systemName: "pawprint.fill")
                .font(.system(size: 60))
                .foregroundColor(.chimpYellow)
                .padding(.bottom, 8)
            
            Text("No Monkeying Around")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            
            Text("Only Chimpin'")
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundColor(.chimpYellow)
            
            if let wallet = walletService.getStoredWallet() {
                Text(wallet.address)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 20)
    }
    
    private var actionCardsSection: some View {
        VStack(spacing: 16) {
            // Load NFT Card
            ActionCard(
                icon: "photo.fill",
                title: "Load NFT",
                description: "Scan an NFC chip to view its NFT",
                color: .blue,
                action: {
                    viewModel.loadNFT()
                }
            )
            
            // Claim NFT Card
            ActionCard(
                icon: "hand.raised.fill",
                title: "Claim NFT",
                description: "Claim ownership of an unclaimed NFT",
                color: .purple,
                action: {
                    viewModel.claimNFT()
                }
            )
            
            // Transfer NFT Card
            ActionCard(
                icon: "arrow.right.circle.fill",
                title: "Transfer NFT",
                description: "Transfer an NFT to another address",
                color: .orange,
                action: {
                    viewModel.transferNFT()
                }
            )
            
            // Sign Message Card
            ActionCard(
                icon: "signature",
                title: "Sign Message",
                description: "Sign a message with your NFC chip",
                color: .green,
                action: {
                    viewModel.signMessage()
                }
            )
            
            // Mint NFT Card (Admin only)
            if AppConfig.shared.isAdminMode {
                ActionCard(
                    icon: "sparkles",
                    title: "Mint NFT",
                    description: "Initialize and mint a new NFT",
                    color: .indigo,
                    action: {
                        viewModel.mintNFT()
                    }
                )
            }
        }
    }
}

