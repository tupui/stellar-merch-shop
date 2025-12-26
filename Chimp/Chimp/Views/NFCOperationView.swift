import SwiftUI

struct NFCOperationView: View {
    let operationType: OperationType
    @Binding var isPresented: Bool
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    
    private let coordinator = NFCOperationCoordinator()
    
    enum OperationType {
        case loadNFT
        case claimNFT
        case transferNFT(recipient: String, tokenId: UInt64)
        case signMessage(message: Data)
        case mintNFT
    }
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                    
                    Text("Processing NFC operation...")
                        .foregroundColor(.white)
                        .font(.system(size: 16, weight: .medium))
                } else if let error = errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.red)
                        
                        Text("Error")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text(error)
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Button("OK") {
                            isPresented = false
                        }
                        .padding(.horizontal, 40)
                        .padding(.vertical, 12)
                        .background(Color.chimpYellow)
                        .foregroundColor(.black)
                        .cornerRadius(8)
                    }
                } else if let success = successMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.green)
                        
                        Text("Success")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text(success)
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Button("OK") {
                            isPresented = false
                        }
                        .padding(.horizontal, 40)
                        .padding(.vertical, 12)
                        .background(Color.chimpYellow)
                        .foregroundColor(.black)
                        .cornerRadius(8)
                    }
                }
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.systemGray6))
            )
            .padding(40)
        }
        .onAppear {
            startOperation()
        }
    }
    
    private func startOperation() {
        isLoading = true
        errorMessage = nil
        successMessage = nil
        
        switch operationType {
        case .loadNFT:
            coordinator.loadNFT { success, error in
                DispatchQueue.main.async {
                    isLoading = false
                    if success {
                        successMessage = "NFT loaded successfully"
                    } else {
                        errorMessage = error ?? "Failed to load NFT"
                    }
                }
            }
            
        case .claimNFT:
            coordinator.claimNFT { success, error in
                DispatchQueue.main.async {
                    isLoading = false
                    if success {
                        successMessage = "NFT claimed successfully"
                    } else {
                        errorMessage = error ?? "Failed to claim NFT"
                    }
                }
            }
            
        case .transferNFT(let recipient, let tokenId):
            coordinator.transferNFT(recipientAddress: recipient, tokenId: tokenId) { success, error in
                DispatchQueue.main.async {
                    isLoading = false
                    if success {
                        successMessage = "NFT transferred successfully"
                    } else {
                        errorMessage = error ?? "Failed to transfer NFT"
                    }
                }
            }
            
        case .signMessage(let message):
            coordinator.signMessage(message: message) { success, globalCounter, keyCounter, signature in
                DispatchQueue.main.async {
                    isLoading = false
                    if success, let gc = globalCounter, let kc = keyCounter, let sig = signature {
                        successMessage = "Signature generated successfully"
                        // Could show signature details here
                    } else {
                        errorMessage = signature ?? "Failed to sign message"
                    }
                }
            }
            
        case .mintNFT:
            coordinator.mintNFT { success, error in
                DispatchQueue.main.async {
                    isLoading = false
                    if success {
                        successMessage = "NFT minted successfully"
                    } else {
                        errorMessage = error ?? "Failed to mint NFT"
                    }
                }
            }
        }
    }
}

