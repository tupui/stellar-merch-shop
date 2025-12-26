import SwiftUI

struct TransferInputView: View {
    @Binding var isPresented: Bool
    @State private var recipientAddress: String = ""
    @State private var tokenIdString: String = ""
    @State private var errorMessage: String?
    
    let onTransfer: (String, UInt64) -> Void
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Transfer Details")) {
                    TextField("Recipient Stellar Address (G...)", text: $recipientAddress)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    
                    TextField("Token ID", text: $tokenIdString)
                        .keyboardType(.numberPad)
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.system(size: 14))
                    }
                }
            }
            .navigationTitle("Transfer NFT")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Transfer") {
                        transfer()
                    }
                    .disabled(recipientAddress.isEmpty || tokenIdString.isEmpty)
                }
            }
        }
    }
    
    private func transfer() {
        errorMessage = nil
        
        guard !recipientAddress.isEmpty else {
            errorMessage = "Please enter a recipient address"
            return
        }
        
        guard !tokenIdString.isEmpty else {
            errorMessage = "Please enter a token ID"
            return
        }
        
        guard AppConfig.shared.validateStellarAddress(recipientAddress) else {
            errorMessage = "Please enter a valid Stellar address (56 characters starting with 'G')"
            return
        }
        
        guard let tokenId = UInt64(tokenIdString) else {
            errorMessage = "Please enter a valid token ID (numeric value)"
            return
        }
        
        isPresented = false
        onTransfer(recipientAddress, tokenId)
    }
}

