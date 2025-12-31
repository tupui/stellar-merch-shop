import SwiftUI

// Preference key to track scroll offset
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @State private var scrollOffset: CGFloat = 0
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background with subtle pattern
                Color.chimpBackground
                    .ignoresSafeArea()
                
                GeometryReader { geometry in
                    ScrollView {
                        VStack(spacing: 24) {
                            // Header with scroll-based zoom
                            headerSection(scrollOffset: scrollOffset)
                                .background(
                                    GeometryReader { headerGeometry in
                                        Color.clear
                                            .preference(
                                                key: ScrollOffsetPreferenceKey.self,
                                                value: -headerGeometry.frame(in: .named("scroll")).minY
                                            )
                                    }
                                )
                            
                            // Error message
                            if let error = viewModel.errorMessage {
                                Text(error)
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundColor(.red)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.red.opacity(0.1))
                                    )
                            }
                            
                            // Main action cards
                            actionCardsSection
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 32)
                    }
                    .coordinateSpace(name: "scroll")
                    .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                        scrollOffset = value
                    }
                }
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
            .alert("Success", isPresented: $viewModel.showingSuccessAlert) {
                Button("OK") {
                    viewModel.showingSuccessAlert = false
                }
            } message: {
                Text(viewModel.successMessage ?? "")
            }
        }
    }
    
    private func headerSection(scrollOffset: CGFloat) -> some View {
        VStack(spacing: 0) {
            // Calculate scale based on scroll offset
            // Logo starts at scale 1.0 and scales down to 0.75 as user scrolls
            let minScale: CGFloat = 0.75
            let maxScroll: CGFloat = 100 // Start scaling after 100pt of scroll
            let scale = max(minScale, 1.0 - min(scrollOffset / maxScroll, 1.0 - minScale))
            
            Image("Logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 140, height: 140)
                .scaleEffect(scale)
                .shadow(color: Color.black.opacity(0.1), radius: 20, x: 0, y: 10)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: scale)
                .padding(.top, 60)
                .padding(.bottom, 70)
        }
    }
    
    private var actionCardsSection: some View {
        VStack(spacing: 20) {
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

