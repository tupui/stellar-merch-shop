import SwiftUI

struct SettingsView: View {
    @ObservedObject var walletState: WalletState
    @State private var network: AppNetwork = AppConfig.shared.currentNetwork
    @State private var contractId: String = AppConfig.shared.contractId
    @State private var showLogoutAlert = false
    @State private var saveStatus: String?
    
    private let walletService = WalletService()
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Network Configuration")) {
                    Picker("Network", selection: $network) {
                        Text("Testnet").tag(AppNetwork.testnet)
                        Text("Mainnet").tag(AppNetwork.mainnet)
                    }
                    
                    TextField("Contract ID", text: $contractId)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    
                    // Show build config info if available
                    if !AppConfig.shared.getBuildConfigContractId().isEmpty {
                        let buildConfigId = AppConfig.shared.getBuildConfigContractId()
                        if contractId.isEmpty {
                            Text("Build config: \(buildConfigId)")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        } else {
                            Text("Build config: \(buildConfigId) (override in field)")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
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
