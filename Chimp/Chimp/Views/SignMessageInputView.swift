import SwiftUI

struct SignMessageInputView: View {
    @Binding var isPresented: Bool
    @State private var messageText: String = ""
    @State private var errorMessage: String?
    
    let onSign: (Data) -> Void
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Message to Sign")) {
                    TextField("Message (hex or text)", text: $messageText)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.system(size: 14))
                    }
                }
            }
            .navigationTitle("Sign Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Sign") {
                        sign()
                    }
                    .disabled(messageText.isEmpty)
                }
            }
        }
    }
    
    private func sign() {
        errorMessage = nil
        
        guard !messageText.isEmpty else {
            errorMessage = "Please enter a message to sign"
            return
        }
        
        // Parse message - could be hex or text
        var messageData: Data
        if messageText.hasPrefix("0x") {
            // Hex string with 0x prefix
            let hexString = String(messageText.dropFirst(2))
            guard isValidHexString(hexString) && hexString.count % 2 == 0,
                  let data = Data(hexString: hexString) else {
                errorMessage = "Please enter valid hexadecimal data"
                return
            }
            messageData = data
        } else if isValidHexString(messageText) && messageText.count % 2 == 0 {
            // Looks like hex without 0x prefix
            guard let data = Data(hexString: messageText) else {
                errorMessage = "Please enter valid hexadecimal data"
                return
            }
            messageData = data
        } else {
            // Treat as text - UTF-8 encoding
            guard let data = messageText.data(using: .utf8) else {
                errorMessage = "Unable to encode message as UTF-8"
                return
            }
            messageData = data
        }
        
        isPresented = false
        onSign(messageData)
    }
    
    private func isValidHexString(_ string: String) -> Bool {
        let hexCharacters = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        return string.unicodeScalars.allSatisfy { hexCharacters.contains($0) }
    }
}

