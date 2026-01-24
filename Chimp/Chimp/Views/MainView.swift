import SwiftUI

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

