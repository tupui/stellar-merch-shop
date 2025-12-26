import SwiftUI
import stellarsdk

struct NFTLoadingView: View {
    let contractId: String
    let tokenId: UInt64
    @Binding var isPresented: Bool
    @State private var metadata: NFTMetadata?
    @State private var imageData: Data?
    @State private var ownerAddress: String?
    @State private var isClaimed: Bool = true
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?
    
    private let blockchainService = BlockchainService()
    private let ipfsService = IPFSService()
    private let walletService = WalletService()
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading NFT...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.red)
                    
                    Text("Error")
                        .font(.system(size: 20, weight: .bold))
                    
                    Text(error)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                    
                    Button("Close") {
                        isPresented = false
                    }
                    .padding(.horizontal, 40)
                    .padding(.vertical, 12)
                    .background(Color.chimpYellow)
                    .foregroundColor(.black)
                    .cornerRadius(8)
                }
                .padding()
            } else if let metadata = metadata {
                NFTDisplayView(
                    metadata: metadata,
                    imageData: imageData,
                    ownerAddress: ownerAddress,
                    isClaimed: isClaimed
                )
            }
        }
        .onAppear {
            loadNFT()
        }
    }
    
    private func loadNFT() {
        Task {
            do {
                guard let wallet = walletService.getStoredWallet(),
                      let privateKey = try SecureKeyStorage().loadPrivateKey() else {
                    await MainActor.run {
                        errorMessage = "No wallet found"
                        isLoading = false
                    }
                    return
                }
                
                let keyPair = try KeyPair(secretSeed: privateKey)
                
                // Try to get the owner - if this succeeds, the NFT is claimed
                do {
                    let owner = try await blockchainService.getTokenOwner(
                        contractId: contractId,
                        tokenId: tokenId,
                        sourceKeyPair: keyPair
                    )
                    await MainActor.run {
                        ownerAddress = owner
                        isClaimed = true
                    }
                } catch let appError as AppError {
                    if case .blockchain(.contract(.tokenNotClaimed)) = appError {
                        await MainActor.run {
                            isClaimed = false
                        }
                    } else {
                        throw appError
                    }
                }
                
                // Get token URI
                let ipfsUrl = try await blockchainService.getTokenUri(
                    contractId: contractId,
                    tokenId: tokenId,
                    sourceKeyPair: keyPair
                )
                
                // Convert IPFS URL to HTTP gateway URL
                let httpMetadataUrl = ipfsService.convertToHTTPGateway(ipfsUrl)
                
                // Download NFT metadata from IPFS
                let downloadedMetadata = try await ipfsService.downloadNFTMetadata(from: httpMetadataUrl)
                
                // Download image if available
                var downloadedImageData: Data? = nil
                if let imageUrl = downloadedMetadata.image {
                    let httpImageUrl = ipfsService.convertToHTTPGateway(imageUrl)
                    downloadedImageData = try await ipfsService.downloadImageData(from: httpImageUrl)
                }
                
                await MainActor.run {
                    metadata = downloadedMetadata
                    imageData = downloadedImageData
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = (error as? AppError)?.localizedDescription ?? "Failed to load NFT information."
                    isLoading = false
                }
            }
        }
    }
}

