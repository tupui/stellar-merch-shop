import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appData: AppData
    @Binding var scannedItem: ScannedItem?
    @State private var selectedFunction: ContractFunctionType? = nil
    @State private var showClaimView = false
    
    enum ContractFunctionType {
        case transfer
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if let item = scannedItem {
                    ScannedItemView(item: item, onDismiss: {
                        scannedItem = nil
                    })
                } else if let function = selectedFunction {
                    FunctionView(functionType: function, onDismiss: {
                        selectedFunction = nil
                    })
                } else if appData.isWalletConnected {
                    mainView
                } else {
                    WalletConnectView()
                }
            }
        }
    }
    
    private var mainView: some View {
        VStack(spacing: 20) {
            Text("NFCMerch")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            if let wallet = appData.walletConnection {
                VStack(spacing: 8) {
                    Text("Connected Wallet:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(wallet.address)
                        .font(.system(.caption, design: .monospaced))
                        .padding(8)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                        .textSelection(.enabled)
                }
                .padding(.horizontal)
            }
            
            VStack(spacing: 15) {
                Button(action: {
                    showClaimView = true
                }) {
                    HStack {
                        Image(systemName: "hand.raised.fill")
                        Text("Claim")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                
                Button(action: {
                    selectedFunction = .transfer
                }) {
                    HStack {
                        Image(systemName: "arrow.right.arrow.left")
                        Text("Transfer")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
            }
            .padding(.horizontal)
            .sheet(isPresented: $showClaimView) {
                ClaimView(
                    contractId: NFCConfig.contractId,
                    onDismiss: {
                        showClaimView = false
                    }
                )
                .environmentObject(appData)
            }
            
            Spacer()
        }
        .padding()
    }
}
