import SwiftUI
import UIKit
import OSLog

struct SettingsView: View {
    @ObservedObject var walletState: WalletState
    @State private var contractId: String = AppConfig.shared.contractId
    @State private var originalContractId: String = ""
    @State private var showLogoutAlert = false
    @State private var showResetAlert = false
    @State private var contractCopied = false
    @State private var saveStatus: String?
    @State private var showHelp = false
    @State private var isAdminMode: Bool = AppConfig.shared.isAdminMode
    @Environment(\.openURL) private var openURL
    
    private let walletService = WalletService()
    private var currentNetwork: AppNetwork {
        AppConfig.shared.currentNetwork
    }
    
    private var config = AppConfig.shared
    
    init(walletState: WalletState) {
        self.walletState = walletState
    }
    
    // Check if contract ID has been modified from original
    private var hasChanges: Bool {
        contractId.trimmingCharacters(in: .whitespacesAndNewlines) != originalContractId.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // Check if current value is at build config default
    private var isAtDefault: Bool {
        let buildConfigId = AppConfig.shared.getBuildConfigContractId()
        let currentId = contractId.trimmingCharacters(in: .whitespacesAndNewlines)
        return currentId == buildConfigId || (currentId.isEmpty && buildConfigId.isEmpty)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // Account Section
                if let wallet = walletService.getStoredWallet() {
                    Section(header: Text("Account")) {
                        WalletAddressCard(
                            address: wallet.address,
                            network: currentNetwork
                        )
                    }
                }
                
                // Admin Settings Section (only visible when admin mode is ON)
                if isAdminMode {
                    Section(header: Text("Admin Settings")) {
                        // Network Configuration (admin only)
                        Picker("Network", selection: Binding(
                            get: { currentNetwork },
                            set: { newNetwork in
                                config.currentNetwork = newNetwork
                            }
                        )) {
                            Text("Testnet").tag(AppNetwork.testnet)
                            Text("Mainnet").tag(AppNetwork.mainnet)
                        }
                        .pickerStyle(.menu)
                        .accessibilityLabel("Network selection")
                        .accessibilityHint("Select between testnet and mainnet")
                        
                        // Contract Configuration
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Contract Address")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            TextField("C...", text: $contractId)
                                .font(.system(.body, design: .monospaced))
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .accessibilityLabel("Contract address")
                                .accessibilityHint("Enter the Stellar contract address starting with C")
                        }
                        
                        if hasChanges {
                            Button(action: saveContractId) {
                                HStack {
                                    if let status = saveStatus {
                                        Label(status, systemImage: "checkmark")
                                            .foregroundColor(.green)
                                    } else {
                                        Text("Save")
                                    }
                                    Spacer()
                                }
                            }
                        }
                        
                        if !contractId.isEmpty {
                            HStack(spacing: 12) {
                                Button(action: copyContractId) {
                                    Label("Copy", systemImage: contractCopied ? "checkmark" : "doc.on.doc")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(contractCopied ? .green : .chimpYellow)
                                }
                                .buttonStyle(PlainButtonStyle())
                                
                                Button(action: openContractStellarExpert) {
                                    Label("View on Stellar.Expert", systemImage: "arrow.up.right.square")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.chimpYellow)
                                }
                                .buttonStyle(PlainButtonStyle())
                                
                                Spacer()
                            }
                        }
                        
                        if !isAtDefault {
                            Button(role: .destructive, action: { showResetAlert = true }) {
                                Text("Reset Contract to Default")
                            }
                        }
                    }
                }
                
                // Help & Support Section
                Section(header: Text("Help & Support")) {
                    Button(action: { showHelp = true }) {
                        Label("Help & Support", systemImage: "questionmark.circle")
                    }
                    .accessibilityLabel("Help and Support")
                    .accessibilityHint("View help documentation and support information")
                }
                
                // Advanced Section
                Section(header: Text("Advanced")) {
                    Toggle(isOn: $isAdminMode) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Admin Mode")
                                .font(.body)
                            Text("Enable admin features like minting NFTs and configuring network settings")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .onChange(of: isAdminMode) { oldValue, newValue in
                        config.isAdminMode = newValue
                    }
                    .accessibilityLabel("Admin Mode")
                    .accessibilityHint("Toggle to enable or disable admin features")
                }
                
                // Logout Section
                Section {
                    Button(role: .destructive, action: { showLogoutAlert = true }) {
                        Text("Logout")
                    }
                    .accessibilityLabel("Logout")
                    .accessibilityHint("Logs out and removes your private key from this device")
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showHelp) {
                NavigationStack {
                    HelpView()
                }
            }
            .alert("Logout", isPresented: $showLogoutAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Logout", role: .destructive) {
                    logout()
                }
            } message: {
                Text("Are you sure you want to logout? Your wallet will be disconnected and your private key will be removed from this device. You will need to enter your secret key again to reconnect.")
            }
            .alert("Reset to Default", isPresented: $showResetAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    resetToDefault()
                }
            } message: {
                Text("This will reset the contract address to the build configuration default. Any custom contract address you've entered will be lost. This action cannot be undone.")
            }
            .onAppear {
                loadCurrentSettings()
                isAdminMode = config.isAdminMode
            }
        }
    }
    
    private func loadCurrentSettings() {
        contractId = AppConfig.shared.contractId
        originalContractId = AppConfig.shared.contractId
    }
    
    private func saveContractId() {
        AppConfig.shared.contractId = contractId.trimmingCharacters(in: .whitespacesAndNewlines)
        originalContractId = contractId.trimmingCharacters(in: .whitespacesAndNewlines)
        
        saveStatus = "Saved"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            saveStatus = nil
        }
    }
    
    private func resetToDefault() {
        // Reset to build configuration defaults
        UserDefaults.standard.removeObject(forKey: "app_contract_id")
        
        contractId = AppConfig.shared.contractId
        originalContractId = AppConfig.shared.contractId
    }
    
    private func openContractStellarExpert() {
        guard !contractId.isEmpty else { return }
        
        let baseUrl: String
        switch currentNetwork {
        case .testnet:
            baseUrl = "https://stellar.expert/explorer/testnet/contract"
        case .mainnet:
            baseUrl = "https://stellar.expert/explorer/public/contract"
        }
        
        let urlString = "\(baseUrl)/\(contractId)"
        guard let url = URL(string: urlString) else { return }
        
        openURL(url)
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
            Logger.logError("Logout error: \(error.localizedDescription)", category: .ui)
        }
    }
}
