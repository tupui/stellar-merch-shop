import SwiftUI

struct NFTDisplayView: View {
    let metadata: NFTMetadata
    let imageData: Data?
    let ownerAddress: String?
    let isClaimed: Bool
    
    var body: some View {
        NFTViewSwiftUI(
            metadata: metadata,
            imageData: imageData,
            ownerAddress: ownerAddress,
            isClaimed: isClaimed
        )
    }
}

