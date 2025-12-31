import SwiftUI

struct WalletAddressCard: View {
    let address: String
    let network: AppNetwork
    @State private var copied = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Wallet Address")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer()
            }
            
            HStack(spacing: 8) {
                Text(address)
                    .font(.system(size: 15, weight: .regular, design: .monospaced))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                
                Spacer()
                
                Button(action: copyAddress) {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 14, weight: .medium))
                        Text(copied ? "Copied" : "Copy")
                            .font(.system(size: 15, weight: .medium))
                    }
                    .foregroundColor(copied ? .green : .chimpYellow)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(copied ? Color.green.opacity(0.1) : Color.chimpYellow.opacity(0.1))
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.vertical, 8)
    }
    
    private func copyAddress() {
        UIPasteboard.general.string = address
        
        withAnimation {
            copied = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                copied = false
            }
        }
    }
}

