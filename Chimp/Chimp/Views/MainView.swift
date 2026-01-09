import SwiftUI
import Combine

@MainActor
class WalletState: ObservableObject {
    @Published var hasWallet: Bool = false
    @Published var walletAddress: String? = nil
    private let walletService = WalletService.shared
    
    init() {
        checkWalletState()
    }
    
    func checkWalletState() {
        if let wallet = walletService.getStoredWallet() {
            hasWallet = true
            walletAddress = wallet.address
        } else {
            hasWallet = false
            walletAddress = nil
        }
    }
}

struct MainView: View {
    @StateObject private var walletState = WalletState()
    
    var body: some View {
        Group {
            if walletState.hasWallet {
                MainTabView(walletState: walletState)
            } else {
                LoginView(walletState: walletState)
            }
        }
    }
}

