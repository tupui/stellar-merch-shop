//
//  LoginView.swift
//  Chimp
//
//  Login view for entering private key
//

import UIKit

class LoginView: UIViewController {
    let TAG: String = "LoginView"
    
    var privateKeyTextField: UITextField!
    var loginButton: UIButton!
    var errorLabel: UILabel!
    var walletService: WalletService!
    
    var onLoginSuccess: (() -> Void)?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        walletService = WalletService()
        configureViews()
    }
    
    func configureViews() {
        view.backgroundColor = .systemBackground
        title = "Login"
        
        // Private key text field
        let textField = UITextField()
        textField.placeholder = "Enter your Stellar secret key (S...)"
        textField.borderStyle = .roundedRect
        textField.isSecureTextEntry = true
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(textField)
        privateKeyTextField = textField
        
        // Login button
        let button = UIButton(type: .system)
        button.setTitle("Login", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        button.backgroundColor = .systemBlue
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 10
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(loginButtonTapped), for: .touchUpInside)
        view.addSubview(button)
        loginButton = button
        
        // Error label
        let label = UILabel()
        label.text = ""
        label.textColor = .systemRed
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 14, weight: .regular)
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        errorLabel = label
        
        // Layout constraints
        NSLayoutConstraint.activate([
            textField.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            textField.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -100),
            textField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            textField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            textField.heightAnchor.constraint(equalToConstant: 44),
            
            button.topAnchor.constraint(equalTo: textField.bottomAnchor, constant: 20),
            button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            button.widthAnchor.constraint(equalToConstant: 200),
            button.heightAnchor.constraint(equalToConstant: 50),
            
            label.topAnchor.constraint(equalTo: button.bottomAnchor, constant: 20),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
    }
    
    @objc func loginButtonTapped() {
        guard let secretKey = privateKeyTextField.text, !secretKey.isEmpty else {
            errorLabel.text = "Please enter your secret key"
            return
        }
        
        loginButton.isEnabled = false
        errorLabel.text = ""
        
        Task {
            do {
                let _ = try await walletService.loadWalletFromSecretKey(secretKey)
                await MainActor.run {
                    self.onLoginSuccess?()
                }
            } catch {
                await MainActor.run {
                    self.errorLabel.text = error.localizedDescription
                    self.loginButton.isEnabled = true
                }
            }
        }
    }
}
