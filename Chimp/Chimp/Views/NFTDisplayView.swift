import SwiftUI
import UIKit

struct NFTDisplayView: UIViewControllerRepresentable {
    let metadata: NFTMetadata
    let imageData: Data?
    let ownerAddress: String?
    let isClaimed: Bool
    
    func makeUIViewController(context: Context) -> UINavigationController {
        let nftView = NFTView()
        nftView.displayNFT(
            metadata: metadata,
            imageData: imageData,
            ownerAddress: ownerAddress,
            isClaimed: isClaimed
        )
        return UINavigationController(rootViewController: nftView)
    }
    
    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
        // No updates needed
    }
}

