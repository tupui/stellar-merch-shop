//
//  SettingsView.swift
//  Chimp
//
//  Settings view for network and contract configuration
//

import UIKit

class SettingsView: UIViewController {
    let TAG: String = "SettingsView"
    
    var networkSegmentedControl: UISegmentedControl!
    var contractIdTextField: UITextField!
    var saveButton: UIButton!
    var logoutButton: UIButton!
    var statusLabel: UILabel!
    
    private let walletService = WalletService()
    var onLogout: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()

        configureViews()
        loadCurrentSettings()
    }
    
    func configureViews() {
        view.backgroundColor = .systemBackground
        title = "Settings"
        
        // Network segmented control
        let segmentedControl = UISegmentedControl(items: ["Testnet", "Mainnet"])
        segmentedControl.selectedSegmentIndex = AppConfig.shared.currentNetwork == .testnet ? 0 : 1
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(segmentedControl)
        networkSegmentedControl = segmentedControl
        
        // Contract ID text field
        let textField = UITextField()
        textField.placeholder = "Contract ID"
        textField.borderStyle = .roundedRect
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(textField)
        contractIdTextField = textField
        
        // Save button
        let saveBtn = UIButton(type: .system)
        saveBtn.setTitle("Save", for: .normal)
        saveBtn.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        saveBtn.backgroundColor = .systemBlue
        saveBtn.setTitleColor(.white, for: .normal)
        saveBtn.layer.cornerRadius = 10
        saveBtn.translatesAutoresizingMaskIntoConstraints = false
        saveBtn.addTarget(self, action: #selector(saveButtonTapped), for: .touchUpInside)
        view.addSubview(saveBtn)
        saveButton = saveBtn
        
        // Logout button
        let logoutBtn = UIButton(type: .system)
        logoutBtn.setTitle("Logout", for: .normal)
        logoutBtn.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        logoutBtn.backgroundColor = .systemRed
        logoutBtn.setTitleColor(.white, for: .normal)
        logoutBtn.layer.cornerRadius = 10
        logoutBtn.translatesAutoresizingMaskIntoConstraints = false
        logoutBtn.addTarget(self, action: #selector(logoutButtonTapped), for: .touchUpInside)
        view.addSubview(logoutBtn)
        logoutButton = logoutBtn
        
        // Status label
        let label = UILabel()
        label.text = ""
        label.textColor = .systemGreen
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 14, weight: .regular)
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        statusLabel = label
        
        // Layout constraints
        NSLayoutConstraint.activate([
            segmentedControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 40),
            segmentedControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            segmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            segmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            textField.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 30),
            textField.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            textField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            textField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            textField.heightAnchor.constraint(equalToConstant: 44),
            
            saveBtn.topAnchor.constraint(equalTo: textField.bottomAnchor, constant: 30),
            saveBtn.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            saveBtn.widthAnchor.constraint(equalToConstant: 200),
            saveBtn.heightAnchor.constraint(equalToConstant: 50),
            
            logoutBtn.topAnchor.constraint(equalTo: saveBtn.bottomAnchor, constant: 30),
            logoutBtn.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            logoutBtn.widthAnchor.constraint(equalToConstant: 200),
            logoutBtn.heightAnchor.constraint(equalToConstant: 50),
            
            label.topAnchor.constraint(equalTo: logoutBtn.bottomAnchor, constant: 30),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
    }
    
    func loadCurrentSettings() {
        networkSegmentedControl.selectedSegmentIndex = AppConfig.shared.currentNetwork == .testnet ? 0 : 1
        
        // Load contract ID (from UserDefaults override or build config)
        let contractId = AppConfig.shared.contractId
        contractIdTextField.text = contractId
        
        // Show placeholder with build config value if available
        let buildConfigId = AppConfig.shared.getBuildConfigContractId()
        if contractId.isEmpty && !buildConfigId.isEmpty {
            contractIdTextField.placeholder = "Build config: \(buildConfigId)"
        } else if !buildConfigId.isEmpty {
            contractIdTextField.placeholder = "Build config: \(buildConfigId) (override in field)"
        } else {
            contractIdTextField.placeholder = "Contract ID (required)"
        }
    }
    
    @objc func saveButtonTapped() {
        // Save network
        AppConfig.shared.currentNetwork = networkSegmentedControl.selectedSegmentIndex == 0 ? .testnet : .mainnet
        
        // Save contract ID
        if let contractId = contractIdTextField.text {
            AppConfig.shared.contractId = contractId
        }
        
        statusLabel.text = "Settings saved!"
        statusLabel.textColor = .systemGreen
        
        // Clear status after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.statusLabel.text = ""
        }
    }
    
    @objc func logoutButtonTapped() {
        let alert = UIAlertController(
            title: "Logout",
            message: "Are you sure you want to logout? Your private key will be removed from this device.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Logout", style: .destructive) { _ in
            do {
                try self.walletService.logout()
                self.onLogout?()
            } catch {
                let errorAlert = UIAlertController(
                    title: "Error",
                    message: error.localizedDescription,
                    preferredStyle: .alert
                )
                errorAlert.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(errorAlert, animated: true)
            }
        })
        
        present(alert, animated: true)
    }
}
