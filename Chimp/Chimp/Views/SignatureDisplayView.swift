import SwiftUI

struct SignatureDisplayView: View {
    let globalCounter: String
    let keyCounter: String
    let derSignature: String
    @Binding var isPresented: Bool
    @State private var copied = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        Text("Signature Generated")
                            .font(.system(size: 20, weight: .semibold))
                            .padding(.top, 20)
                        
                        VStack(alignment: .leading, spacing: 16) {
                            InfoRow(title: "Global Counter:", value: globalCounter)
                            InfoRow(title: "Key Counter:", value: keyCounter)
                            InfoRow(title: "DER Signature:", value: derSignature)
                        }
                        .padding(.horizontal, 20)
                        
                        Button(action: copySignature) {
                            HStack {
                                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                Text(copied ? "Copied!" : "Copy Signature")
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Color.chimpYellow)
                            .foregroundColor(.black)
                            .cornerRadius(8)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
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
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.primary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

