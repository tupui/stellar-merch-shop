import SwiftUI
import UIKit

struct SettingsView: View {
    @ObservedObject var walletState: WalletState
    @State private var network: AppNetwork = AppConfig.shared.currentNetwork
    @State private var contractId: String = AppConfig.shared.contractId
    @State private var showLogoutAlert = false
    @State private var saveStatus: String?
    @State private var contractCopied = false
    
    private let walletService = WalletService()
    
    var body: some View {
        NavigationView {
            Form {
                // Wallet Address Section
                if let wallet = walletService.getStoredWallet() {
                    Section(header: Text("Wallet")) {
                        WalletAddressCard(
                            address: wallet.address,
                            network: network
                        )
                    }
                }
                
                Section(header: Text("Smart Contract")) {
                    Picker("Network", selection: $network) {
                        Text("Testnet").tag(AppNetwork.testnet)
                        Text("Mainnet").tag(AppNetwork.mainnet)
                    }
                    
                    HStack {
                        TextField("Address", text: $contractId)
                            .font(.system(size: 15, design: .monospaced))
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        
                        if !contractId.isEmpty {
                            Button(action: copyContractId) {
                                Image(systemName: contractCopied ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(contractCopied ? .green : .chimpYellow)
                                    .frame(width: 32, height: 32)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                
                Section {
                    Button(action: saveSettings) {
                        HStack {
                            Text("Save Settings")
                            Spacer()
                            if let status = saveStatus {
                                Text(status)
                                    .foregroundColor(.green)
                            }
                        }
                    }
                    
                    Button(action: resetToDefault) {
                        HStack {
                            Text("Reset to Default")
                            Spacer()
                        }
                    }
                }
                
                Section {
                    Button(action: { showLogoutAlert = true }) {
                        Text("Logout")
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Settings")
            .alert("Logout", isPresented: $showLogoutAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Logout", role: .destructive) {
                    logout()
                }
            } message: {
                Text("Are you sure you want to logout? Your private key will be removed from this device.")
            }
            .onAppear {
                loadCurrentSettings()
            }
        }
    }
    
    private func loadCurrentSettings() {
        network = AppConfig.shared.currentNetwork
        contractId = AppConfig.shared.contractId
    }
    
    private func saveSettings() {
        AppConfig.shared.currentNetwork = network
        AppConfig.shared.contractId = contractId
        
        saveStatus = "Saved!"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            saveStatus = nil
        }
    }
    
    private func resetToDefault() {
        // Reset to build configuration defaults
        UserDefaults.standard.removeObject(forKey: "app_network")
        UserDefaults.standard.removeObject(forKey: "app_contract_id")
        
        network = AppConfig.shared.currentNetwork
        contractId = AppConfig.shared.contractId
        
        saveStatus = "Reset!"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            saveStatus = nil
        }
    }
    
    private func copyContractId() {
        guard !contractId.isEmpty else { return }
        
        UIPasteboard.general.string = contractId
        
        withAnimation {
            contractCopied = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                contractCopied = false
            }
        }
    }
    
    private func logout() {
        do {
            try walletService.logout()
            walletState.checkWalletState()
            } catch {
            // Error handling could be improved with an alert
            print("Logout error: \(error.localizedDescription)")
        }
    }
}
