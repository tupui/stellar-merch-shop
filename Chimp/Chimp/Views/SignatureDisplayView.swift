import SwiftUI

struct SignatureDisplayView: View {
    let globalCounter: UInt32
    let keyCounter: UInt32
    let derSignature: String
    @Binding var isPresented: Bool
    @State private var copied = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        Text("Signature Generated")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .padding(.top, 20)
                            .accessibilityAddTraits(.isHeader)
                        
                        VStack(alignment: .leading, spacing: 16) {
                            InfoRow(title: "Global Counter:", value: String(globalCounter))
                            InfoRow(title: "Key Counter:", value: String(keyCounter))
                            InfoRow(title: "DER Signature:", value: derSignature)
                        }
                        .padding(.horizontal, 20)
                        
                        Button(action: copySignature) {
                            HStack {
                                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                Text(copied ? "Copied!" : "Copy Signature")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .accessibilityLabel(copied ? "Signature copied" : "Copy signature")
                        .accessibilityHint("Copies the signature to your clipboard")
                    }
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle("Signature")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        isPresented = false
                    }
                }
            }
        }
    }
    
    private func copySignature() {
        let signatureText = "Global Counter: \(globalCounter)\nKey Counter: \(keyCounter)\nDER Signature: \(derSignature)"
        UIPasteboard.general.string = signatureText
        
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

struct InfoRow: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.subheadline)
                .foregroundColor(.primary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

