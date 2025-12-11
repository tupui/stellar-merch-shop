/**
 * Wallet Connect View
 * UI for entering manual secret key
 */

import SwiftUI

struct WalletConnectView: View {
    @EnvironmentObject var appData: AppData
    @State private var secretKey = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?
    
    var body: some View {
        if appData.isWalletConnected {
            connectedWalletView
        } else {
            VStack(spacing: 20) {
                Text("Connect Wallet")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Enter your Stellar secret key")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                SecureField("Secret Key (S...)", text: $secretKey)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .padding(.horizontal)
                
                Button("Connect") {
                    Task {
                        await connectSecretKey()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(secretKey.isEmpty || isConnecting)
                .padding(.horizontal)
                
                if isConnecting {
                    ProgressView()
                }
                
                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding()
                }
            }
            .padding()
        }
    }
    
    @ViewBuilder
    private var connectedWalletView: some View {
        VStack(spacing: 15) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 50))
                .foregroundColor(.green)
            
            Text("Wallet Connected")
                .font(.headline)
            
            if let wallet = appData.walletConnection {
                VStack(spacing: 8) {
                    Text("Address:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(wallet.address)
                        .font(.system(.caption, design: .monospaced))
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                        .textSelection(.enabled)
                }
                .padding()
            }
            
            Button("Disconnect") {
                appData.walletConnection = nil
                UserDefaults.standard.removeObject(forKey: "wallet_address")
            }
            .buttonStyle(.bordered)
            .foregroundColor(.red)
        }
        .padding()
    }
    
    private func connectSecretKey() async {
        isConnecting = true
        errorMessage = nil
        
        do {
            let connection = try await appData.walletService.loadWalletFromSecretKey(secretKey)
            appData.walletConnection = connection
            secretKey = ""
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isConnecting = false
    }
}

