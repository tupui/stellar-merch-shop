import SwiftUI

struct TransferInputView: View {
    @Binding var isPresented: Bool
    @State private var recipientAddress: String = ""
    @State private var tokenIdString: String = ""
    @State private var errorMessage: String?
    @State private var showConfirmation = false
    
    let onTransfer: (String, UInt64) -> Void
    
    private var isRecipientValid: Bool {
        !recipientAddress.isEmpty && AppConfig.shared.validateStellarAddress(recipientAddress)
    }
    
    private var isTokenIdValid: Bool {
        !tokenIdString.isEmpty && UInt64(tokenIdString) != nil
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Transfer Details")) {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Recipient Stellar Address (G...)", text: $recipientAddress)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .accessibilityLabel("Recipient address")
                            .accessibilityHint("Enter the Stellar address starting with G")
                        
                        if !recipientAddress.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: isRecipientValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(isRecipientValid ? .green : .red)
                                Text(isRecipientValid ? "Valid address" : "Invalid address format")
                                    .font(.caption)
                                    .foregroundColor(isRecipientValid ? .green : .red)
                            }
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Token ID", text: $tokenIdString)
                            .keyboardType(.numberPad)
                            .accessibilityLabel("Token ID")
                            .accessibilityHint("Enter the numeric token ID to transfer")
                        
                        if !tokenIdString.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: isTokenIdValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(isTokenIdValid ? .green : .red)
                                Text(isTokenIdValid ? "Valid token ID" : "Invalid token ID")
                                    .font(.caption)
                                    .foregroundColor(isTokenIdValid ? .green : .red)
                            }
                        }
                    }
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.subheadline)
                            .accessibilityLabel("Error: \(error)")
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
                        validateAndShowConfirmation()
                    }
                    .disabled(!isRecipientValid || !isTokenIdValid)
                }
            }
            .alert("Confirm Transfer", isPresented: $showConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Transfer", role: .destructive) {
                    transfer()
                }
            } message: {
                Text("You are about to transfer this NFT. This action cannot be undone.\n\nRecipient: \(recipientAddress)\nToken ID: \(tokenIdString)")
            }
        }
    }
    
    private func validateAndShowConfirmation() {
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
        
        guard let _ = UInt64(tokenIdString) else {
            errorMessage = "Please enter a valid token ID (numeric value)"
            return
        }
        
        showConfirmation = true
    }
    
    private func transfer() {
        guard let tokenId = UInt64(tokenIdString) else {
            errorMessage = "Invalid token ID"
            return
        }
        
        isPresented = false
        onTransfer(recipientAddress, tokenId)
    }
}

