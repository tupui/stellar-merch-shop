import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @ObservedObject private var appConfig = AppConfig.shared
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background with subtle pattern
                Color.chimpBackground
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 0) {
                        // Header with logo
                        headerSection
                        
                        VStack(spacing: 16) {
                            // Error message
                            if let error = viewModel.errorMessage {
                                ErrorBanner(
                                    error: error,
                                    onDismiss: {
                                        viewModel.dismissError()
                                    },
                                    onRetry: nil, // Can be enhanced to track last operation
                                    onCheckSettings: (error.lowercased().contains("contract") || error.lowercased().contains("settings")) ? {
                                        // User can navigate to Settings tab manually
                                        viewModel.dismissError()
                                    } : nil
                                )
                                .padding(.horizontal, 20)
                                .padding(.top, 16)
                                .transition(.move(edge: .top).combined(with: .opacity))
                            }
                            
                            // Main action cards
                            actionCardsSection
                                .padding(.horizontal, 20)
                                .padding(.top, viewModel.errorMessage == nil ? 16 : 0)
                        }
                        .animation(.easeInOut(duration: 0.3), value: viewModel.errorMessage)
                        .padding(.bottom, 24)
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    // Empty toolbar to remove default title
                }
            }
            .overlay {
                // Confetti overlay for success animations
                if viewModel.showingConfetti {
                    ConfettiOverlay(message: viewModel.confettiMessage ?? "")
                        .transition(.opacity)
                        .zIndex(1000)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: viewModel.showingConfetti)
            .sheet(isPresented: $viewModel.showingNFTView) {
                if let contractId = viewModel.loadedNFTContractId,
                   let tokenId = viewModel.loadedNFTTokenId {
                    NavigationStack {
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
            .sheet(isPresented: $viewModel.showingSignatureView) {
                if let signature = viewModel.signatureData {
                    SignatureDisplayView(
                        globalCounter: signature.globalCounter,
                        keyCounter: signature.keyCounter,
                        derSignature: signature.derSignature,
                        isPresented: $viewModel.showingSignatureView
                    )
                }
            }
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 0) {
            Image("Logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 100, height: 100)
                .shadow(color: Color.black.opacity(0.08), radius: 16, x: 0, y: 8)
                .padding(.top, 20)
                .padding(.bottom, 20)
                .accessibilityLabel("Chimp logo")
        }
    }
    
    private var actionCardsSection: some View {
        VStack(spacing: 16) {
            // Empty state if contract ID not configured
            if AppConfig.shared.contractId.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 50))
                        .foregroundColor(.orange)
                    
                    Text("Contract Not Configured")
                        .font(.headline)
                    
                    Text("Please set the contract address in Settings to use claim, transfer, and mint operations.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.systemGray6))
                )
            }
            
            // Load NFT Card
            ActionCard(
                icon: "photo.fill",
                title: "Load NFT",
                description: "Hold your iPhone near an NFC chip to view its NFT details and metadata",
                color: .blue,
                action: {
                    viewModel.loadNFT()
                }
            )
            
            // Claim NFT Card (reads contract ID from chip NDEF)
            ActionCard(
                icon: "hand.raised.fill",
                title: "Claim NFT",
                description: "Claim ownership of an unclaimed NFT by holding your iPhone near the chip",
                color: .purple,
                action: {
                    viewModel.claimNFT()
                }
            )
            
            // Transfer NFT Card (reads contract ID from chip NDEF)
            ActionCard(
                icon: "arrow.right.circle.fill",
                title: "Transfer NFT",
                description: "Transfer an NFT to another Stellar address. You'll need the recipient address and token ID",
                color: .orange,
                action: {
                    viewModel.transferNFT()
                }
            )
            
            // Sign Message Card
            ActionCard(
                icon: "signature",
                title: "Sign Message",
                description: "Sign a message or 32-byte hex value using your NFC chip's private key",
                color: .green,
                action: {
                    viewModel.signMessage()
                }
            )
            
            // Mint NFT Card (Admin only, requires contract ID)
            if appConfig.isAdminMode && !appConfig.contractId.isEmpty {
                ActionCard(
                    icon: "sparkles",
                    title: "Mint NFT",
                    description: "Initialize and mint a new NFT. Hold your iPhone near the chip to begin",
                    color: .indigo,
                    action: {
                        viewModel.mintNFT()
                    }
                )
            }
        }
    }
}

