//
//  ViewController.swift
//  Chimp
//
//  Based on Infineon BlockchainSecurity2Go-iOS template
//

import UIKit
import CoreNFC
import stellarsdk

/// Simple confetti animation view for success celebrations
class ConfettiView: UIView {
    private var emitterLayer: CAEmitterLayer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupConfetti()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupConfetti()
    }

    private func setupConfetti() {
        let emitter = CAEmitterLayer()
        // Position and size will be set in layoutSubviews
        emitter.emitterShape = .line
        emitter.birthRate = 0 // Start stopped

        // Create confetti particles
        var cells = [CAEmitterCell]()

        let colors: [UIColor] = [.systemBlue, .systemGreen, .systemPurple, .systemOrange, .systemPink]
        _ = ["circle", "triangle", "square"] // shapes not currently used

        for (index, color) in colors.enumerated() {
            let cell = CAEmitterCell()
            cell.birthRate = 3.0 // More particles for better visibility
            cell.lifetime = 8.0 // Longer lifetime
            cell.velocity = 150 + CGFloat(index * 20) // Moderate fall speed
            cell.velocityRange = 50 // Less variation in speed
            cell.emissionLongitude = .pi // Straight down
            cell.emissionRange = .pi / 3 // Narrower spread (60 degrees) for more focused effect
            cell.spin = 1.5
            cell.spinRange = 2
            cell.scale = 0.25 // Much larger for better visibility
            cell.scaleRange = 0.15 // More consistent size
            cell.alphaSpeed = -0.06 // Slightly slower fade

            // Create larger colored shapes for better visibility
            let shapeSize = CGSize(width: 12, height: 12)
            UIGraphicsBeginImageContextWithOptions(shapeSize, false, 0)
            color.setFill()
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: shapeSize)).fill()
            let image = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()

            cell.contents = image?.cgImage
            cells.append(cell)
        }

        emitter.emitterCells = cells
        layer.addSublayer(emitter)
        emitterLayer = emitter
    }

    func startConfetti() {
        emitterLayer?.birthRate = 1.0

        // Stop after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.stopConfetti()
        }
    }

    func stopConfetti() {
        emitterLayer?.birthRate = 0
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Update emitter position and size when view bounds change
        emitterLayer?.emitterPosition = CGPoint(x: bounds.midX, y: bounds.minY - 20)
        emitterLayer?.emitterSize = CGSize(width: bounds.width * 1.5, height: 4)
    }
}

/// Modal view controller for displaying signature results with copy functionality
class SignaturePopupViewController: UIViewController {

    private let globalCounter: String
    private let keyCounter: String
    private let derSignature: String

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Signature Generated"
        label.font = .systemFont(ofSize: 20, weight: .semibold)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var contentStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var copyButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Copy Signature", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        button.backgroundColor = .systemBlue
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 8
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(copySignature), for: .touchUpInside)
        return button
    }()

    private lazy var closeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Close", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .regular)
        button.setTitleColor(.systemBlue, for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(closePopup), for: .touchUpInside)
        return button
    }()

    init(globalCounter: String, keyCounter: String, derSignature: String) {
        self.globalCounter = globalCounter
        self.keyCounter = keyCounter
        self.derSignature = derSignature
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    private func setupUI() {
        view.backgroundColor = UIColor.black.withAlphaComponent(0.5)

        // Container view for the popup content
        let containerView = UIView()
        containerView.backgroundColor = .systemBackground
        containerView.layer.cornerRadius = 12
        containerView.layer.masksToBounds = true
        containerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(containerView)

        // Add title
        containerView.addSubview(titleLabel)

        // Create content labels
        let globalCounterLabel = createInfoLabel(title: "Global Counter:", value: globalCounter)
        let keyCounterLabel = createInfoLabel(title: "Key Counter:", value: keyCounter)
        let signatureLabel = createInfoLabel(title: "DER Signature:", value: derSignature)

        // Add labels to stack view
        contentStackView.addArrangedSubview(globalCounterLabel)
        contentStackView.addArrangedSubview(keyCounterLabel)
        contentStackView.addArrangedSubview(signatureLabel)

        containerView.addSubview(contentStackView)

        // Button stack
        let buttonStack = UIStackView()
        buttonStack.axis = .horizontal
        buttonStack.spacing = 12
        buttonStack.distribution = .fillEqually
        buttonStack.translatesAutoresizingMaskIntoConstraints = false

        buttonStack.addArrangedSubview(closeButton)
        buttonStack.addArrangedSubview(copyButton)

        containerView.addSubview(buttonStack)

        // Layout constraints
        NSLayoutConstraint.activate([
            containerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            containerView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            titleLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),

            contentStackView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 20),
            contentStackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            contentStackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),

            buttonStack.topAnchor.constraint(equalTo: contentStackView.bottomAnchor, constant: 24),
            buttonStack.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            buttonStack.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),
            buttonStack.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -20),
            buttonStack.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func createInfoLabel(title: String, value: String) -> UIView {
        let container = UIView()

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .secondaryLabel
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.font = .systemFont(ofSize: 14, weight: .regular)
        valueLabel.textColor = .label
        valueLabel.numberOfLines = 0
        valueLabel.lineBreakMode = .byCharWrapping
        valueLabel.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(titleLabel)
        container.addSubview(valueLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            valueLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            valueLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            valueLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            valueLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        return container
    }

    @objc private func copySignature() {
        let signatureText = "Global Counter: \(globalCounter)\nKey Counter: \(keyCounter)\nDER Signature: \(derSignature)"
        UIPasteboard.general.string = signatureText

        // Show brief feedback
        let originalTitle = copyButton.title(for: .normal)
        copyButton.setTitle("Copied!", for: .normal)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.copyButton.setTitle(originalTitle, for: .normal)
        }
    }

    @objc private func closePopup() {
        dismiss(animated: true)
    }
}

/// Contains the user interface controller code of the main screen
class ViewController: UIViewController, NFCTagReaderSessionDelegate {
    let TAG: String = "MainViewController"
    
    var scanButton: UIButton!
    var signButton: UIButton!
    var claimButton: UIButton!
    var transferButton: UIButton!
    var mintButton: UIButton!
    var addressLabel: UILabel!
    var settingsButton: UIButton!
    var loadingIndicator: UIActivityIndicatorView!

    var nfc_helper: NFCHelper?
    var session: NFCTagReaderSession?
    private let walletService = WalletService()
    private let claimService = ClaimService()
    private let transferService = TransferService()
    private let mintService = MintService()
    private let blockchainService = BlockchainService()
    private let ipfsService = IPFSService()
    var confettiView: ConfettiView?
    
    /// Stores the key index selected by the user. Default value is 1
    var selected_keyindex: UInt8  = 0x01

    /// Operation type: true for signature, false for read
    var isSignOperation: Bool = false

    /// Transfer operation parameters
    var transferRecipientAddress: String?
    var transferTokenId: UInt64?

    
    // MARK: - View controller events
    override func viewDidLoad() {
        super.viewDidLoad()

        ConfigureViews()
        ResetDefaults()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // Check for stored wallet after view is in hierarchy
        if walletService.getStoredWallet() == nil {
            showLoginView()
        } else {
            updateUIForLoggedInState()
        }
    }
    
    // MARK: - Event handlers
    @objc func LoadNFTButtonTapped() {
        print(TAG + ": Load NFT button clicked")

        guard walletService.getStoredWallet() != nil else {
            showLoginView()
            return
        }

        ResetDefaults()
        scanButton.isEnabled = false
        loadingIndicator.startAnimating()

        // Start NFC session to read chip data and get token ID
        startLoadNFTSession()
    }

    /// Start NFC session for loading NFT (reads contract ID from NDEF and public key from chip)
    private func startLoadNFTSession() {
        print(TAG + ": Starting Load NFT NFC session")

        guard NFCTagReaderSession.readingAvailable else {
            DispatchQueue.main.async {
                self.showNFTError("NFC is not available on this device")
                self.enableAllButtons()
                self.loadingIndicator.stopAnimating()
            }
            return
        }

        session = NFCTagReaderSession(pollingOption: .iso14443, delegate: self, queue: nil)
        session?.alertMessage = "Tap NFC chip to load NFT"
        session?.begin()
    }

    // MARK: - NFCTagReaderSessionDelegate Methods

    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        print(TAG + ": Load NFT session became active")
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        print(TAG + ": Load NFT session invalidated with error: \(error)")
        DispatchQueue.main.async {
            self.enableAllButtons()
            self.loadingIndicator.stopAnimating()
            if let nfcError = error as? NFCReaderError {
                switch nfcError.code {
                case .readerSessionInvalidationErrorUserCanceled:
                    // User canceled, no need to show error
                    break
                default:
                    self.showNFTError("NFC Error: \(error.localizedDescription)")
                }
            }
        }
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        print(TAG + ": Load NFT session detected \(tags.count) tags")

        guard let firstTag = tags.first else {
            session.invalidate(errorMessage: "No NFC tag found")
            return
        }

        Task {
            do {
                try await self.handleLoadNFTTag(tag: firstTag, session: session)
            } catch {
                await MainActor.run {
                    let errorMessage = (error as? AppError)?.localizedDescription ?? "Failed to load NFT"
                    session.invalidate(errorMessage: errorMessage)
                }
            }
        }
    }

    /// Handle Load NFT tag detection - read NDEF and chip public key
    private func handleLoadNFTTag(tag: NFCTag, session: NFCTagReaderSession) async throws {
        guard case .iso7816(let iso7816Tag) = tag else {
            throw AppError.nfc(.invalidTag)
        }

        session.connect(to: tag) { [weak self] error in
            if let error = error {
                print((self?.TAG ?? "ViewController") + ": Failed to connect to tag: \(error)")
                session.invalidate(errorMessage: "Failed to connect to NFC tag")
                return
            }
        }

        // First, read NDEF to get contract ID using APDU commands
        let ndefUrl = try await readNDEFUrl(tag: iso7816Tag, session: session)
        guard let ndefUrl = ndefUrl else {
            throw AppError.nfc(.readWriteFailed("No NDEF URL found"))
        }

        print(TAG + ": NDEF URL read: \(ndefUrl)")

        // Parse contract ID from URL
        guard let contractId = parseContractIdFromNDEFUrl(ndefUrl) else {
            throw AppError.validation("Invalid contract ID in NFC tag")
        }

        print(TAG + ": Parsed contract ID: \(contractId)")

        // Now read the chip's public key
        let chipPublicKey = try await readChipPublicKey(tag: iso7816Tag, session: session, keyIndex: 0x01)
        print(TAG + ": Read chip public key: \(chipPublicKey)")

        // Convert public key string to Data
        guard let publicKeyData = Data(hexString: chipPublicKey) else {
            throw AppError.crypto(.invalidKey("Invalid public key format from chip"))
        }

        // Get token ID for this chip
        let tokenId = try await getTokenIdForChip(contractId: contractId, publicKey: publicKeyData)
        print(TAG + ": Got token ID \(tokenId) for chip")

        // Close NFC session
        await MainActor.run {
            session.invalidate()
        }

        // Check wallet exists for contract calls
        guard walletService.getStoredWallet() != nil else {
            throw AppError.nft(.noWallet)
        }

        // Get private key from secure storage
        let secureStorage = SecureKeyStorage()
        guard let privateKey = try secureStorage.loadPrivateKey() else {
            throw AppError.nft(.noWallet)
        }
        let keyPair = try KeyPair(secretSeed: privateKey)

        // Try to get the owner - if this succeeds, the NFT is claimed
        do {
            print(TAG + ": Checking ownership for token \(tokenId)")
            let ownerAddress = try await blockchainService.getTokenOwner(
                contractId: contractId,
                tokenId: tokenId,
                sourceKeyPair: keyPair
            )
            print(TAG + ": Token \(tokenId) has owner: \(ownerAddress), loading as claimed NFT")
            // NFT has an owner, load as claimed
            try await loadNFT(contractId: contractId, tokenId: tokenId, keyPair: keyPair)
        } catch let appError as AppError {
            // Check if this is a contract error indicating the token is not claimed
            if case .blockchain(.contract(.tokenNotClaimed)) = appError {
                print(TAG + ": Token \(tokenId) is unclaimed, loading as unclaimed NFT")
                try await loadUnclaimedNFT(contractId: contractId, tokenId: tokenId, keyPair: keyPair)
            } else {
                print(TAG + ": Token \(tokenId) ownership check failed with unexpected error: \(appError)")
                throw appError
            }
        } catch {
            print(TAG + ": Token \(tokenId) ownership check failed with unknown error: \(error), trying as unclaimed NFT")
            // For backward compatibility, treat unknown errors as unclaimed
            try await loadUnclaimedNFT(contractId: contractId, tokenId: tokenId, keyPair: keyPair)
        }
    }

    /// Parse contract ID from NDEF URL (extracts the contract ID part)
    private func parseContractIdFromNDEFUrl(_ url: String) -> String? {
        // Remove protocol if present
        var urlPath = url
        if urlPath.hasPrefix("http://") {
            urlPath = String(urlPath.dropFirst(7))
        } else if urlPath.hasPrefix("https://") {
            urlPath = String(urlPath.dropFirst(8))
        }

        // Split by '/' and expect contract ID as second component
        let components = urlPath.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count >= 2 else {
            return nil
        }

        let contractId = String(components[1])

        // Validate contract ID format
        guard contractId.count == 56 && contractId.hasPrefix("C") else {
            return nil
        }

        return contractId
    }

    /// Get token ID for a chip's public key
    private func getTokenIdForChip(contractId: String, publicKey: Data) async throws -> UInt64 {
        print(TAG + ": Getting token ID for chip with public key: \(publicKey.map { String(format: "%02x", $0) }.joined())")

        // Create keypair for contract calls
        guard walletService.getStoredWallet() != nil,
              let privateKey = try SecureKeyStorage().loadPrivateKey() else {
            throw AppError.wallet(.noWallet)
        }

        let keyPair = try KeyPair(secretSeed: privateKey)

        // Use the blockchain service method
        return try await blockchainService.getTokenId(contractId: contractId, publicKey: publicKey, sourceKeyPair: keyPair)
    }

    // MARK: - NDEF Reading (copied from NFCHelper)

    /// NDEF Application ID
    private let NDEF_AID: [UInt8] = [0xD2, 0x76, 0x00, 0x00, 0x85, 0x01, 0x01]

    /// NDEF File ID
    private let NDEF_FILE_ID: [UInt8] = [0xE1, 0x04]

    /// Read NDEF URL from chip using APDU commands
    private func readNDEFUrl(tag: NFCISO7816Tag, session: NFCTagReaderSession) async throws -> String? {
        print(TAG + ": Reading NDEF URL...")

        do {
            // Step 1: Select NDEF Application
            guard let selectAppAPDU = NFCISO7816APDU(data: Data([0x00, 0xA4, 0x04, 0x00] + [UInt8(NDEF_AID.count)] + NDEF_AID + [0x00])) else {
                print(TAG + ": Failed to create SELECT NDEF Application APDU")
                return nil
            }
            let (_, selectAppSW1, selectAppSW2) = try await tag.sendCommand(apdu: selectAppAPDU)

            guard selectAppSW1 == 0x90 && selectAppSW2 == 0x00 else {
                print(TAG + ": Failed to select NDEF application: \(selectAppSW1) \(selectAppSW2)")
                return nil
            }
            print(TAG + ": NDEF Application selected")

            // Step 2: Select NDEF File
            guard let selectFileAPDU = NFCISO7816APDU(data: Data([0x00, 0xA4, 0x00, 0x0C, 0x02] + NDEF_FILE_ID)) else {
                print(TAG + ": Failed to create SELECT NDEF File APDU")
                return nil
            }
            let (_, selectFileSW1, selectFileSW2) = try await tag.sendCommand(apdu: selectFileAPDU)

            guard selectFileSW1 == 0x90 && selectFileSW2 == 0x00 else {
                print(TAG + ": Failed to select NDEF file: \(selectFileSW1) \(selectFileSW2)")
                return nil
            }
            print(TAG + ": NDEF File selected")

            // Step 3: Read NLEN (2 bytes at offset 0) to get NDEF message length
            guard let readNlenAPDU = NFCISO7816APDU(data: Data([0x00, 0xB0, 0x00, 0x00, 0x02])) else {
                print(TAG + ": Failed to create READ NLEN APDU")
                return nil
            }
            let (readNlenData, readNlenSW1, readNlenSW2) = try await tag.sendCommand(apdu: readNlenAPDU)

            guard readNlenSW1 == 0x90 && readNlenSW2 == 0x00 else {
                print(TAG + ": Failed to read NLEN: \(readNlenSW1) \(readNlenSW2)")
                return nil
            }

            let nlen = UInt16(readNlenData[0]) << 8 | UInt16(readNlenData[1])
            if nlen == 0 {
                print(TAG + ": No NDEF data (NLEN = 0)")
                return nil
            }

            print(TAG + ": NLEN = \(nlen) bytes")

            // Step 4: Read actual NDEF data (starting from offset 2)
            var ndefData = Data()
            var currentOffset: UInt16 = 2
            let maxReadLength: UInt8 = 255 - 2

            while ndefData.count < Int(nlen) {
                let bytesToRead = min(Int(nlen) - ndefData.count, Int(maxReadLength))

                guard let readBinaryAPDU = NFCISO7816APDU(data: Data([
                    0x00, 0xB0,
                    UInt8((currentOffset >> 8) & 0xFF),
                    UInt8(currentOffset & 0xFF),
                    UInt8(bytesToRead)
                ])) else {
                    print(TAG + ": Failed to create READ BINARY APDU")
                    return nil
                }

                let (readData, readSW1, readSW2) = try await tag.sendCommand(apdu: readBinaryAPDU)

                guard readSW1 == 0x90 && readSW2 == 0x00 else {
                    print(TAG + ": Failed to read NDEF data chunk: \(readSW1) \(readSW2)")
                    return nil
                }

                ndefData.append(readData)
                currentOffset += UInt16(bytesToRead)
            }

            // Parse the NDEF URL
            return parseNDEFUrl(from: ndefData)

        } catch {
            print(TAG + ": Error reading NDEF: \(error)")
            throw error
        }
    }

    /// Parse NDEF URL record from raw data
    private func parseNDEFUrl(from data: Data) -> String? {
        guard data.count >= 7 else {
            print(TAG + ": NDEF data too short")
            return nil
        }

        // Parse NDEF record
        let flags = data[0]
        let typeLength = data[1]
        let payloadLength = data[2]
        let typeStart = 3
        let payloadStart = typeStart + Int(typeLength)

        guard data.count >= payloadStart + Int(payloadLength) else {
            print(TAG + ": NDEF data truncated")
            return nil
        }

        let typeData = data.subdata(in: typeStart..<payloadStart)
        let payloadData = data.subdata(in: payloadStart..<payloadStart + Int(payloadLength))

        // Check if this is a URI record
        guard typeData.count == 1 && typeData[0] == 0x55 else { // URI record type
            print(TAG + ": Not a URI record")
            return nil
        }

        // Parse URI payload
        guard payloadData.count >= 1 else {
            print(TAG + ": URI payload too short")
            return nil
        }

        let uriIdentifierCode = payloadData[0]
        let uriData = payloadData.subdata(in: 1..<payloadData.count)

        // URI identifier codes (RFC 3986)
        let uriPrefixes = [
            "", // 0x00: no prefix
            "http://www.", // 0x01
            "https://www.", // 0x02
            "http://", // 0x03
            "https://", // 0x04
            "tel:", // 0x05
            "mailto:", // 0x06
            "ftp://anonymous:anonymous@", // 0x07
            "ftp://ftp.", // 0x08
            "ftps://", // 0x09
            "sftp://", // 0x0A
            "smb://", // 0x0B
            "nfs://", // 0x0C
            "ftp://", // 0x0D
            "dav://", // 0x0E
            "news:", // 0x0F
            "telnet://", // 0x10
            "imap:", // 0x11
            "rtsp://", // 0x12
            "urn:", // 0x13
            "pop:", // 0x14
            "sip:", // 0x15
            "sips:", // 0x16
            "tftp:", // 0x17
            "btspp://", // 0x18
            "btl2cap://", // 0x19
            "btgoep://", // 0x1A
            "tcpobex://", // 0x1B
            "irdaobex://", // 0x1C
            "file://", // 0x1D
            "urn:epc:id:", // 0x1E
            "urn:epc:tag:", // 0x1F
            "urn:epc:pat:", // 0x20
            "urn:epc:raw:", // 0x21
            "urn:epc:", // 0x22
            "urn:nfc:" // 0x23
        ]

        var prefix = ""
        if Int(uriIdentifierCode) < uriPrefixes.count {
            prefix = uriPrefixes[Int(uriIdentifierCode)]
        }

        guard let uriString = String(data: uriData, encoding: .utf8) else {
            print(TAG + ": Failed to decode URI string")
            return nil
        }

        let fullUrl = prefix + uriString
        print(TAG + ": Successfully parsed NDEF URL: \(fullUrl)")
        return fullUrl
    }

    /// Read public key from chip
    private func readChipPublicKey(tag: NFCISO7816Tag, session: NFCTagReaderSession, keyIndex: UInt8) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let commandHandler = BlockchainCommandHandler(tag_iso7816: tag, reader_session: session)
            commandHandler.ActionGetKey(key_index: keyIndex) { success, response, error, session in
                if success, let response = response, response.count >= 73 {
                    // Extract public key (skip first 9 bytes: 4 bytes global counter + 4 bytes signature counter + 1 byte 0x04)
                    let publicKeyData = response.subdata(in: 9..<73) // 64 bytes of public key
                    // Add 0x04 prefix for uncompressed format
                    var fullPublicKey = Data([0x04])
                    fullPublicKey.append(publicKeyData)
                    let publicKeyHex = fullPublicKey.map { String(format: "%02x", $0) }.joined()
                    continuation.resume(returning: publicKeyHex)
                } else {
                    continuation.resume(throwing: AppError.nfc(.chipError(error ?? "Failed to read chip public key")))
                }
            }
        }
    }

    /// Handles immediate NFC error feedback
    func OnImmediateError(error: String) {
        DispatchQueue.main.async {
            self.loadingIndicator.stopAnimating()
            self.scanButton.isEnabled = true
        }
    }

    /// Handles NDEF reading events
    func OnNDEFEvent(success: Bool, url: String?, error: String?) {
        if success, let ndefUrl = url {
            print(TAG + ": NDEF URL read: \(ndefUrl)")

            // Parse URL to extract contract ID and token ID
            if let (contractId, tokenId) = parseNDEFUrl(ndefUrl) {
                print(TAG + ": Parsed contract ID: \(contractId), token ID: \(tokenId)")

                // Show immediate success feedback and close NFC session
                DispatchQueue.main.async {
                    self.loadingIndicator.stopAnimating()
                    self.enableAllButtons()

                    // Close NFC session immediately - we have the data we need
                    self.nfc_helper?.EndSession()
                    self.nfc_helper = nil
                }

                // Load the NFT in background (ownership check and metadata download can fail)
                Task {
                    do {
                        // First check if the NFT has an owner
                        let wallet = self.walletService.getStoredWallet()
                        guard wallet != nil else {
                            throw AppError.nft(.noWallet)
                        }

                        let secureStorage = SecureKeyStorage()
                        guard let privateKey = try secureStorage.loadPrivateKey() else {
                            throw AppError.nft(.noWallet)
                        }
                        let keyPair = try KeyPair(secretSeed: privateKey)

                        // Try to get the owner - if this succeeds, the NFT is claimed
                        do {
                            print("LoadNFT: Checking ownership for token \(tokenId)")
                            let ownerAddress = try await self.blockchainService.getTokenOwner(
                                contractId: contractId,
                                tokenId: tokenId,
                                sourceKeyPair: keyPair
                            )
                            print("LoadNFT: Token \(tokenId) has owner: \(ownerAddress), loading as claimed NFT")
                            // NFT has an owner, load as claimed
                            try await self.loadNFT(contractId: contractId, tokenId: tokenId, keyPair: keyPair)
                        } catch let appError as AppError {
                            // Check if this is a contract error indicating the token is not claimed
                            if case .blockchain(.contract(.tokenNotClaimed)) = appError {
                                print("LoadNFT: Token \(tokenId) is unclaimed, loading as unclaimed NFT")
                                try await self.loadUnclaimedNFT(contractId: contractId, tokenId: tokenId, keyPair: keyPair)
                            } else {
                                print("LoadNFT: Token \(tokenId) ownership check failed with unexpected error: \(appError)")
                                throw appError
                            }
                        } catch {
                            print("LoadNFT: Token \(tokenId) ownership check failed with unknown error: \(error), trying as unclaimed NFT")
                            // For backward compatibility, treat unknown errors as unclaimed
                            try await self.loadUnclaimedNFT(contractId: contractId, tokenId: tokenId, keyPair: keyPair)
                        }
                    } catch let _ as AppError {
                        // Error will be handled in the NFT view if needed
                    } catch {
                        // Error will be handled in the NFT view if needed
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.loadingIndicator.stopAnimating()
                    self.enableAllButtons()
                    self.nfc_helper?.EndSession()
                    self.nfc_helper = nil
                }
            }
        } else {
            // Show error immediately when NFC reading fails
            DispatchQueue.main.async {
                self.loadingIndicator.stopAnimating()
                self.enableAllButtons()
            }
        }
    }

    /// Parse NDEF URL to extract contract ID and token ID
    /// Expected format: [base]/[contractID]/[token_id]
    private func parseNDEFUrl(_ url: String) -> (contractId: String, tokenId: UInt64)? {
        // Remove protocol if present
        var urlPath = url
        if urlPath.hasPrefix("http://") {
            urlPath = String(urlPath.dropFirst(7))
        } else if urlPath.hasPrefix("https://") {
            urlPath = String(urlPath.dropFirst(8))
        }

        // Split by '/' and expect at least 3 parts: [base]/[contractID]/[token_id]
        let components = urlPath.split(separator: "/", omittingEmptySubsequences: true)
        print(TAG + ": URL path components: \(components)")
        guard components.count >= 3 else {
            print(TAG + ": URL doesn't have expected format (need at least 3 components): \(url)")
            return nil
        }

        // Contract ID is typically the second-to-last component
        // Token ID is the last component
        let contractId = String(components[components.count - 2])
        let tokenIdString = String(components[components.count - 1])

        print(TAG + ": Parsed contractId: \(contractId), tokenIdString: \(tokenIdString)")

        // Validate contract ID format (should be 56 characters, start with 'C')
        guard contractId.count == 56 && contractId.hasPrefix("C") else {
            print(TAG + ": Invalid contract ID format (should be 56 chars starting with 'C'): \(contractId)")
            return nil
        }

        // Parse token ID
        guard let tokenId = UInt64(tokenIdString) else {
            print(TAG + ": Invalid token ID format (must be numeric): \(tokenIdString)")
            return nil
        }

        // Additional validation: token ID shouldn't be unreasonably large
        guard tokenId <= UInt64.max / 2 else {
            print(TAG + ": Token ID too large: \(tokenId)")
            return nil
        }

        print(TAG + ": Successfully parsed token ID: \(tokenId)")

        return (contractId, tokenId)
    }

    @objc func ScanButtonTapped() {
        print(TAG + ": Read card button clicked")

        ResetDefaults()
        selected_keyindex = 0x01
        isSignOperation = false
        BeginNFCReadSession()
    }
    
    @objc func SignButtonTapped() {
        print(TAG + ": Sign message button clicked")

        // Show input dialog for message to sign
        showSignMessageInputDialog()
    }
    
    @objc func ClaimButtonTapped() {
        print(TAG + ": Claim button clicked")
        
        guard walletService.getStoredWallet() != nil else {
            showLoginView()
            return
        }
        
        guard !AppConfig.shared.contractId.isEmpty else {
            let alert = UIAlertController(
                title: "Contract ID Required",
                message: "Please set the contract ID in Settings",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        
        ResetDefaults()
        claimButton.isEnabled = false
        
        BeginNFCClaimSession()
    }

    @objc func TransferButtonTapped() {
        print(TAG + ": Transfer button clicked")

        guard walletService.getStoredWallet() != nil else {
            showLoginView()
            return
        }

        guard !AppConfig.shared.contractId.isEmpty else {
            let alert = UIAlertController(
                title: "Contract ID Required",
                message: "Please set the contract ID in Settings",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }

        // Show transfer input dialog
        showTransferInputDialog()
    }

    @objc func MintButtonTapped() {
        print(TAG + ": Mint button clicked")

        guard walletService.getStoredWallet() != nil else {
            showLoginView()
            return
        }

        guard !AppConfig.shared.contractId.isEmpty else {
            let alert = UIAlertController(
                title: "Contract ID Required",
                message: "Please set the contract ID in Settings",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }

        ResetDefaults()
        mintButton.isEnabled = false

        BeginNFCMintSession()
    }

    @objc func SettingsButtonTapped() {
        let settingsView = SettingsView()
        settingsView.onLogout = { [weak self] in
            self?.showLoginView()
        }
        let navController = UINavigationController(rootViewController: settingsView)
        present(navController, animated: true)
    }
    
    // MARK: - Private helpers: UI
    /// Configures the user interface elements and assigns the respective event handlers
    func ConfigureViews(){
        view.backgroundColor = .systemBackground
        title = "Chimp"
        
        // Settings button
        let settingsBtn = UIBarButtonItem(
            image: UIImage(systemName: "gearshape"),
            style: .plain,
            target: self,
            action: #selector(SettingsButtonTapped)
        )
        navigationItem.rightBarButtonItem = settingsBtn
        settingsButton = UIButton()
        
        // Address label
        let addrLabel = UILabel()
        addrLabel.text = ""
        addrLabel.textAlignment = .center
        addrLabel.numberOfLines = 0
        addrLabel.font = .systemFont(ofSize: 12, weight: .regular)
        addrLabel.textColor = .secondaryLabel
        addrLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(addrLabel)
        addressLabel = addrLabel
        
        // Create load NFT button
        let button = UIButton(type: .system)
        button.setTitle("Load NFT", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        button.backgroundColor = .systemBlue
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 10
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(LoadNFTButtonTapped), for: .touchUpInside)
        view.addSubview(button)
        scanButton = button
        
        // Create sign button
        let signBtn = UIButton(type: .system)
        signBtn.setTitle("Sign Message", for: .normal)
        signBtn.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        signBtn.backgroundColor = .systemGreen
        signBtn.setTitleColor(.white, for: .normal)
        signBtn.layer.cornerRadius = 10
        signBtn.translatesAutoresizingMaskIntoConstraints = false
        signBtn.addTarget(self, action: #selector(SignButtonTapped), for: .touchUpInside)
        view.addSubview(signBtn)
        signButton = signBtn
        
        // Create claim button
        let claimBtn = UIButton(type: .system)
        claimBtn.setTitle("Claim NFT", for: .normal)
        claimBtn.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        claimBtn.backgroundColor = .systemPurple
        claimBtn.setTitleColor(.white, for: .normal)
        claimBtn.layer.cornerRadius = 10
        claimBtn.translatesAutoresizingMaskIntoConstraints = false
        claimBtn.addTarget(self, action: #selector(ClaimButtonTapped), for: .touchUpInside)
        view.addSubview(claimBtn)
        claimButton = claimBtn

        // Create transfer button
        let transferBtn = UIButton(type: .system)
        transferBtn.setTitle("Transfer NFT", for: .normal)
        transferBtn.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        transferBtn.backgroundColor = .systemOrange
        transferBtn.setTitleColor(.white, for: .normal)
        transferBtn.layer.cornerRadius = 10
        transferBtn.translatesAutoresizingMaskIntoConstraints = false
        transferBtn.addTarget(self, action: #selector(TransferButtonTapped), for: .touchUpInside)
        view.addSubview(transferBtn)
        transferButton = transferBtn

        // Create mint button
        let mintBtn = UIButton(type: .system)
        mintBtn.setTitle("Mint NFT", for: .normal)
        mintBtn.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        mintBtn.backgroundColor = .systemIndigo
        mintBtn.setTitleColor(.white, for: .normal)
        mintBtn.layer.cornerRadius = 10
        mintBtn.translatesAutoresizingMaskIntoConstraints = false
        mintBtn.addTarget(self, action: #selector(MintButtonTapped), for: .touchUpInside)
        view.addSubview(mintBtn)
        mintButton = mintBtn

        // Create loading indicator
        let loading = UIActivityIndicatorView(style: .medium)
        loading.translatesAutoresizingMaskIntoConstraints = false
        loading.hidesWhenStopped = true
        loading.color = .systemBlue
        view.addSubview(loading)
        loadingIndicator = loading

        // Create confetti view for success celebrations
        let confetti = ConfettiView(frame: view.bounds)
        confetti.translatesAutoresizingMaskIntoConstraints = false
        confetti.isHidden = true
        view.addSubview(confetti)
        confettiView = confetti
        
        // Layout constraints
        NSLayoutConstraint.activate([
            addrLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            addrLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            addrLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -150),
            button.widthAnchor.constraint(equalToConstant: 200),
            button.heightAnchor.constraint(equalToConstant: 50),

            signBtn.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            signBtn.topAnchor.constraint(equalTo: button.bottomAnchor, constant: 20),
            signBtn.widthAnchor.constraint(equalToConstant: 200),
            signBtn.heightAnchor.constraint(equalToConstant: 50),

            claimBtn.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            claimBtn.topAnchor.constraint(equalTo: signBtn.bottomAnchor, constant: 20),
            claimBtn.widthAnchor.constraint(equalToConstant: 200),
            claimBtn.heightAnchor.constraint(equalToConstant: 50),

            transferBtn.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            transferBtn.topAnchor.constraint(equalTo: claimBtn.bottomAnchor, constant: 20),
            transferBtn.widthAnchor.constraint(equalToConstant: 200),
            transferBtn.heightAnchor.constraint(equalToConstant: 50),

            mintBtn.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            mintBtn.topAnchor.constraint(equalTo: transferBtn.bottomAnchor, constant: 20),
            mintBtn.widthAnchor.constraint(equalToConstant: 200),
            mintBtn.heightAnchor.constraint(equalToConstant: 50),

            // Confetti view fills entire screen
            confetti.topAnchor.constraint(equalTo: view.topAnchor),
            confetti.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            confetti.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            confetti.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            loading.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loading.topAnchor.constraint(equalTo: mintBtn.bottomAnchor, constant: 20)
        ])
    }
    
    func updateUIForLoggedInState() {
        if let wallet = walletService.getStoredWallet() {
            addressLabel.text = "Address: \(wallet.address)"
            claimButton.isHidden = false
        } else {
            addressLabel.text = ""
            claimButton.isHidden = true
        }
    }
    
    func showLoginView() {
        // Only show if not already presented
        guard presentedViewController == nil else {
            return
        }
        
        let loginView = LoginView()
        loginView.onLoginSuccess = { [weak self] in
            self?.dismiss(animated: true) {
                self?.updateUIForLoggedInState()
            }
        }
        let navController = UINavigationController(rootViewController: loginView)
        navController.modalPresentationStyle = .fullScreen
        present(navController, animated: true)
    }
    
    /// Resets the user interface elements to the initial state
    func ResetDefaults() {
        self.loadingIndicator.stopAnimating()
        self.confettiView?.stopConfetti()
        self.confettiView?.isHidden = true
    }

    /// Enables all buttons in the UI
    func enableAllButtons() {
        self.scanButton.isEnabled = true
        self.signButton.isEnabled = true
        self.claimButton.isEnabled = true
        self.transferButton.isEnabled = true
        self.mintButton.isEnabled = true
    }


    /// Ensures clean view controller state before presenting alerts
    private func ensureCleanUIState() {
        // Dismiss any presented view controllers to prevent UI conflicts
        if let presentedVC = presentedViewController {
            presentedVC.dismiss(animated: false, completion: nil)
        }

        // Reset any active first responders to clear keyboard state
        view.endEditing(true)
    }
    
    // MARK: - Private helpers: NFC
    /// Begins NFC session for claim operation
    func BeginNFCClaimSession() {
        guard NFCTagReaderSession.readingAvailable else {
            let alert = UIAlertController(
                title: "No NFC",
                message: "NFC is not available on this device",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            claimButton.isEnabled = true
            return
        }
        
        nfc_helper = NFCHelper()
        nfc_helper?.OnTagEvent = self.OnClaimTagEvent(success:tag:session:error:)
        nfc_helper?.BeginSession()
    }

    /// Begins NFC session for transfer operation
    func BeginNFCTransferSession(recipientAddress: String, tokenId: UInt64) {
        guard NFCTagReaderSession.readingAvailable else {
            let alert = UIAlertController(
                title: "No NFC",
                message: "NFC is not available on this device",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            transferButton.isEnabled = true
            return
        }

        // Store transfer parameters for use in callback
        transferRecipientAddress = recipientAddress
        transferTokenId = tokenId

        nfc_helper = NFCHelper()
        nfc_helper?.OnTagEvent = self.OnTransferTagEvent(success:tag:session:error:)
        nfc_helper?.BeginSession()
    }

    /// Begins NFC session for mint operation
    func BeginNFCMintSession() {
        guard NFCTagReaderSession.readingAvailable else {
            let alert = UIAlertController(
                title: "No NFC",
                message: "NFC is not available on this device",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            mintButton.isEnabled = true
            return
        }

        nfc_helper = NFCHelper()
        nfc_helper?.OnTagEvent = self.OnMintTagEvent(success:tag:session:error:)
        nfc_helper?.BeginSession()
    }

    /// Handles tag events for claim operation
    func OnClaimTagEvent(success: Bool, tag: NFCISO7816Tag?,
                        session: NFCTagReaderSession?, error: String?) {
        if success {
            if let tag = tag, let session = session {
                // Show loading state immediately on main thread
                Task { @MainActor in
                    self.loadingIndicator.startAnimating()
                    session.alertMessage = "Processing claim... Please wait."
                }

                // Run blockchain operations on background thread
                Task.detached {
                    do {
                        let claimResult = try await self.claimService.executeClaim(
                            tag: tag,
                            session: session,
                            keyIndex: self.selected_keyindex
                        ) { progress in
                            Task { @MainActor in
                                session.alertMessage = progress
                            }
                        }

                        // Success - update UI on main thread
                        await MainActor.run {
                            self.confettiView?.isHidden = false
                            self.confettiView?.startConfetti()
                            self.enableAllButtons()
                            self.loadingIndicator.stopAnimating()
                            session.alertMessage = "Claim successful!"
                        }

                        // Wait for confetti animation, then invalidate session and load NFT on background thread
                        try await Task.sleep(nanoseconds: 3_000_000_000)

                        await MainActor.run {
                            session.invalidate()
                        }

                        Task.detached {
                            do {
                                // Get keyPair for NFT loading
                                guard self.walletService.getStoredWallet() != nil else {
                                    await MainActor.run {
                                        self.showNFTError("No wallet found")
                                    }
                                    return
                                }

                                let secureStorage = SecureKeyStorage()
                                guard let privateKey = try secureStorage.loadPrivateKey() else {
                                    await MainActor.run {
                                        self.showNFTError("No private key found")
                                    }
                                    return
                                }
                                let keyPair = try KeyPair(secretSeed: privateKey)

                                try await self.loadNFT(contractId: AppConfig.shared.contractId, tokenId: claimResult.tokenId, keyPair: keyPair)
                            } catch {
                                await MainActor.run {
                                    self.showNFTError("Failed to load NFT after claim")
                                }
                            }
                        }
                    } catch {
                        // Error - update UI on main thread
                        await MainActor.run {
                            let errorMessage = (error as? AppError)?.localizedDescription ?? "Claim failed"
                            self.enableAllButtons()
                            self.loadingIndicator.stopAnimating()
                            session.invalidate(errorMessage: errorMessage)
                        }
                    }
                }
            }
        } else {
            DispatchQueue.main.async {
                self.claimButton.isEnabled = true
            }
        }
    }

    /// Handles tag events for transfer operation
    func OnTransferTagEvent(success: Bool, tag: NFCISO7816Tag?,
                           session: NFCTagReaderSession?, error: String?) {
        if success {
            if let tag = tag, let session = session {
                guard let recipientAddress = transferRecipientAddress,
                      let tokenId = transferTokenId else {
                    DispatchQueue.main.async {
                        self.enableAllButtons()
                    }
                    session.invalidate(errorMessage: "Transfer parameters not set")
                    return
                }

                // Show loading state immediately
                Task { @MainActor in
                    self.loadingIndicator.startAnimating()
                    session.alertMessage = "Processing transfer... Please wait."
                }

                // Run blockchain operations on background thread
                Task.detached {
                    do {
                        _ = try await self.transferService.executeTransfer(
                            tag: tag,
                            session: session,
                            keyIndex: self.selected_keyindex,
                            recipientAddress: recipientAddress,
                            tokenId: tokenId
                        ) { progress in
                            Task { @MainActor in
                                session.alertMessage = progress
                            }
                        }

                        // Success - update UI
                        await MainActor.run {
                            self.confettiView?.isHidden = false
                            self.confettiView?.startConfetti()
                            self.loadingIndicator.stopAnimating()
                            session.alertMessage = "Transfer successful!"
                        }

                        // After confetti animation, show success message and clean up session
                        try await Task.sleep(nanoseconds: 3_000_000_000)

                        await MainActor.run {
                            self.ensureCleanUIState()

                            let alert = UIAlertController(
                                title: "Transfer Successful",
                                message: "Token \(tokenId) has been successfully transferred to \(recipientAddress)",
                                preferredStyle: .alert
                            )
                            alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
                                self?.enableAllButtons()
                            })
                            self.present(alert, animated: true)

                            // Invalidate session after showing the alert
                            session.invalidate()

                            // Clear transfer parameters
                            self.transferRecipientAddress = nil
                            self.transferTokenId = nil
                        }
                    } catch {
                        // Error - update UI
                        await MainActor.run {
                            let errorMessage = (error as? AppError)?.localizedDescription ?? "Transfer failed"
                            self.enableAllButtons()
                            self.loadingIndicator.stopAnimating()
                            session.invalidate(errorMessage: errorMessage)

                            // Clear transfer parameters
                            self.transferRecipientAddress = nil
                            self.transferTokenId = nil
                        }
                    }
                }
            }
        } else {
            DispatchQueue.main.async {
                self.transferButton.isEnabled = true
                // Clear transfer parameters on failure
                self.transferRecipientAddress = nil
                self.transferTokenId = nil
            }
        }
    }

    /// Handles tag events for mint operation
    func OnMintTagEvent(success: Bool, tag: NFCISO7816Tag?,
                        session: NFCTagReaderSession?, error: String?) {
        if success {
            if let tag = tag, let session = session {
                // Show loading state immediately
                Task { @MainActor in
                    self.loadingIndicator.startAnimating()
                    session.alertMessage = "Processing mint... Please wait."
                }

                // Run blockchain operations on background thread
                Task.detached {
                    do {
                        let mintResult = try await self.mintService.executeMint(
                            tag: tag,
                            session: session,
                            keyIndex: self.selected_keyindex
                        ) { progress in
                            Task { @MainActor in
                                session.alertMessage = progress
                            }
                        }

                        // Success - update UI
                        await MainActor.run {
                            self.confettiView?.isHidden = false
                            self.confettiView?.startConfetti()
                            self.loadingIndicator.stopAnimating()
                            self.enableAllButtons()
                            session.alertMessage = "Mint successful!"
                        }

                        // After confetti animation, show success message and clean up session
                        try await Task.sleep(nanoseconds: 3_000_000_000)

                        await MainActor.run {
                            self.ensureCleanUIState()

                            let alert = UIAlertController(
                                title: "Mint Successful",
                                message: "Token \(mintResult.tokenId) has been successfully minted to your wallet",
                                preferredStyle: .alert
                            )
                            alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
                                self?.enableAllButtons()
                            })
                            self.present(alert, animated: true)

                            // Invalidate session after showing the alert
                            session.invalidate()
                        }
                    } catch {
                        // Error - update UI
                        await MainActor.run {
                            let errorMessage = (error as? AppError)?.localizedDescription ?? "Mint failed"
                            self.enableAllButtons()
                            self.loadingIndicator.stopAnimating()
                            session.invalidate(errorMessage: errorMessage)
                        }
                    }
                }
            }
        } else {
            DispatchQueue.main.async {
                self.mintButton.isEnabled = true
            }
        }
    }

    /// Checks for NFC support and begins a tag reader session
    func BeginNFCReadSession() {
        
        // Check whether NFC is supported in this device
        guard NFCTagReaderSession.readingAvailable else {
            print(TAG + ": Device doesn't support NFC")
            
            let alert = UIAlertController(
                title: "No NFC",
                message: "NFC is not available on this device",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(
                title: "OK",
                style: .default, handler: nil))
            self.present(alert, animated: true, completion: nil)
            return
        }
        
        // Begin the NFC reader session
        nfc_helper = NFCHelper()
        nfc_helper?.OnTagEvent = self.OnTagEvent(success:tag:session:error:)
        nfc_helper?.BeginSession()
    }
    
    /// Handles the initial tag events such as tag presented, timeout, etc. of the NFCHelper class
    /// - Parameters:
    ///   - success: Indicates whether the tag is detected successfully
    ///   - tag: ISO7816 tag handle for further communication with the tag. nil if tag not detected.
    ///   - session: NFCTagReaderSession handle for further communication with the tag. nil if tag not detected.
    ///   - error: Error description in case of tag detection failure
    func OnTagEvent(success: Bool, tag: NFCISO7816Tag?,
                    session: NFCTagReaderSession?, error: String?) {
        if(success){
            // If the tag reader session handle is available, start sending the commands
            if(tag != nil && session != nil){
                SendBlockchainCommand(tag: tag!, session: session!)
            }
        }
        else {
            // Failed to detect tag. Display failure
            var error_message: String = "Failed to detect tag. "
            if(error != nil) {
                error_message += error!
            }
            // Error handled silently - no status text displayed
        }
    }
    
    /// Exchanges Blockchain commands to read the public key or generate signature from the tag
    /// - Parameters:
    ///   - tag: ISO7816 tag handle for communication with the tag
    ///   - session: NFCTagReaderSession handle for communication with the tag
    func SendBlockchainCommand(tag: NFCISO7816Tag, session: NFCTagReaderSession)
    {
        let command_handler: BlockchainCommandHandler = BlockchainCommandHandler(tag_iso7816: tag, reader_session: session)
        
        if isSignOperation {
            // Use custom message if provided, otherwise fall back to test hash
            let messageDigest: Data
            if let customMessage = customMessageToSign {
                messageDigest = customMessage
                print(TAG + ": Using custom message for signing")
                print(TAG + ": Custom message length: \(customMessage.count) bytes")
                print(TAG + ": Custom message (hex): \(customMessage.map { String(format: "%02x", $0) }.joined())")
            } else {
                // Fallback to test hash
                let testHashHex = "53d79d1d1cdcb175a480d34dddf359d3bf9f441d35d5e86b8a3ea78afba9491b"
                guard let testData = Data(hexString: testHashHex) else {
                    print(TAG + ": Error: Failed to parse test hash")
                    session.invalidate(errorMessage: "Invalid test hash")
                    return
                }
                messageDigest = testData
                print(TAG + ": Using test hash (fallback)")
                print(TAG + ": Message digest (hex): \(testHashHex)")
            }

            print(TAG + ": Starting signature generation")
            print(TAG + ": Key index: \(selected_keyindex)")
            command_handler.ActionGenerateSignature(key_index: selected_keyindex, message_digest: messageDigest, completion_handler: OnSignCommandCompleted)
        } else {
            command_handler.ActionGetKey(key_index: selected_keyindex, completion_handler: OnCommandCompleted)
        }
    }
    
    /// Handles the action completed event for BlockchainCommandHandler. This processes the result of the APDU exchanges.
    /// - Parameters:
    ///   - success: Indicates whether the GetKey action is completed successfully
    ///   - response: APDU response of GetKey command without SW
    ///   - session: NFCTagReaderSession handle for invalidating the session
    /// - Returns: Nothing
    func OnCommandCompleted(success: Bool, response: Data?, error: String?, session: NFCTagReaderSession) -> Void{
        
        var result: Bool = false
        var error_msg: String = ""
        if(error != nil) {
            error_msg = error!
        }
        
        if(success && (response != nil)){
            print(TAG + ": Response from card: " + (response?.hexEncodedString() ?? ""))
            
            // Extract public key (skip first 9 bytes: 4 bytes global counter + 4 bytes signature counter + 1 byte 0x04)
            if response!.count >= 73 {
                let publicKeyData = response!.subdata(in: 9..<73) // 64 bytes of public key
                _ = publicKeyData.map { String(format: "%02x", $0) }.joined()
                
                result = true
                // Public key read successfully - no display needed
                print(TAG + ": Success: Public key displayed")
            } else {
                error_msg = "Invalid response length"
                print(TAG + ": Invalid response length: \(response!.count)")
            }
        }

        if(result)
        {
            // Success
            session.alertMessage = "Completed successfully"
            session.invalidate()
        } else {

            DispatchQueue.main.async {
                self.enableAllButtons()
            }
             session.invalidate(errorMessage: "Failed to read tag. \(error_msg)")
        }
    }
    
    /// Handles the signature generation completed event for BlockchainCommandHandler
    /// - Parameters:
    ///   - success: Indicates whether the signature generation is completed successfully
    ///   - response: APDU response of GenerateSignature command without SW
    ///   - session: NFCTagReaderSession handle for invalidating the session
    func OnSignCommandCompleted(success: Bool, response: Data?, error: String?, session: NFCTagReaderSession) -> Void {
        
        var result: Bool = false
        var error_msg: String = ""
        if(error != nil) {
            error_msg = error!
        }
        
        if(success && (response != nil)){
            print(TAG + ": Signature response from card: " + (response?.hexEncodedString() ?? ""))
            
            // Response format: 4 bytes global counter + 4 bytes key counter + DER signature
            if response!.count >= 8 {
                let globalCounter = response!.subdata(in: 0..<4)
                let keyCounter = response!.subdata(in: 4..<8)
                let derSignature = response!.subdata(in: 8..<response!.count)
                
                let globalCounterHex = globalCounter.hexEncodedString()
                let keyCounterHex = keyCounter.hexEncodedString()
                let derSignatureHex = derSignature.hexEncodedString()
                
                print(TAG + ": ========== SIGNATURE GENERATION RESULT ==========")
                print(TAG + ": Global counter (hex): \(globalCounterHex)")
                print(TAG + ": Key counter (hex): \(keyCounterHex)")
                print(TAG + ": DER signature (hex): \(derSignatureHex)")
                print(TAG + ": DER signature length: \(derSignature.count) bytes")
                print(TAG + ": Full response (hex): \(response!.hexEncodedString())")
                print(TAG + ": ================================================")
                
                result = true
                // Show signature popup
                DispatchQueue.main.async {
                    let popup = SignaturePopupViewController(
                        globalCounter: globalCounterHex,
                        keyCounter: keyCounterHex,
                        derSignature: derSignatureHex
                    )
                    self.present(popup, animated: true)
                }
                print(TAG + ": Success: Signature displayed")
            } else {
                error_msg = "Invalid response length: \(response!.count) bytes (expected at least 8)"
                print(TAG + ": Invalid response length: \(response!.count)")
            }
        }

        // Clear the custom message after use
        customMessageToSign = nil

        if(result)
        {
            // Success
            session.alertMessage = "Signature generated successfully"
            session.invalidate()
        } else {
            DispatchQueue.main.async {
                self.enableAllButtons()
            }
            session.invalidate(errorMessage: "Failed to generate signature. \(error_msg)")
        }
    }

    // MARK: - NFT Loading
    private func loadUnclaimedNFT(contractId: String, tokenId: UInt64, keyPair: KeyPair) async throws {
        do {
            // Status updates removed - no status text displayed

            // First check if the token exists by getting its URI
            let ipfsUrl = try await blockchainService.getTokenUri(
                contractId: contractId,
                tokenId: tokenId,
                sourceKeyPair: keyPair
            )

            // Status updates removed - no status text displayed

            // Convert IPFS URL to HTTP gateway URL
            let httpMetadataUrl = ipfsService.convertToHTTPGateway(ipfsUrl)

            // Download NFT metadata from IPFS
            let metadata = try await ipfsService.downloadNFTMetadata(from: httpMetadataUrl)

            // Download image if available
            var imageData: Data? = nil
            if let imageUrl = metadata.image {
                let httpImageUrl = ipfsService.convertToHTTPGateway(imageUrl)
                imageData = try await ipfsService.downloadImageData(from: httpImageUrl)
            }

            // Show NFT view with unclaimed status
            await MainActor.run {
                let nftView = NFTView()
                nftView.displayNFT(metadata: metadata, imageData: imageData, ownerAddress: nil, isClaimed: false)
                let navController = UINavigationController(rootViewController: nftView)
                present(navController, animated: true)

                // Always update UI state when NFT loading completes
                self.loadingIndicator.stopAnimating()
                enableAllButtons()
            }

        } catch let appError as AppError {
            // Handle different error types appropriately
            await MainActor.run {
                self.showNFTError(appError.localizedDescription)
            }
        } catch {
            await MainActor.run {
                self.showNFTError("Failed to load NFT information.")
            }
        }
    }

    private func loadNFT(contractId: String, tokenId: UInt64, keyPair: KeyPair) async throws {
        do {
            // Status updates removed - no status text displayed

            // First check if the token exists by getting its URI
            let ipfsUrl = try await blockchainService.getTokenUri(
                contractId: contractId,
                tokenId: tokenId,
                sourceKeyPair: keyPair
            )

            await MainActor.run {
                // Status updates removed - no status text displayed
            }

            // Now check if the token has an owner
            let ownerAddress = try await blockchainService.getTokenOwner(
                contractId: contractId,
                tokenId: tokenId,
                sourceKeyPair: keyPair
            )

            await MainActor.run {
                // Status updates removed - no status text displayed
            }

            // Status updates removed - no status text displayed

            // Convert IPFS URL to HTTP gateway URL
            let httpMetadataUrl = ipfsService.convertToHTTPGateway(ipfsUrl)

            // Download NFT metadata from IPFS
            let metadata = try await ipfsService.downloadNFTMetadata(from: httpMetadataUrl)

            // Download image if available
            var imageData: Data? = nil
            if let imageUrl = metadata.image {
                let httpImageUrl = ipfsService.convertToHTTPGateway(imageUrl)
                imageData = try await ipfsService.downloadImageData(from: httpImageUrl)
            }

            // Show NFT view with owner information
            await MainActor.run {
                let nftView = NFTView()
                nftView.displayNFT(metadata: metadata, imageData: imageData, ownerAddress: ownerAddress, isClaimed: true)
                let navController = UINavigationController(rootViewController: nftView)
                present(navController, animated: true)

                // Always update UI state when NFT loading completes
                self.loadingIndicator.stopAnimating()
                enableAllButtons()
            }

        } catch let appError as AppError {
            // Handle different error types appropriately
            await MainActor.run {
                self.showNFTError(appError.localizedDescription)
            }
        } catch {
            await MainActor.run {
                self.showNFTError("Failed to load NFT information.")
            }
        }
    }

    /// Shows an error alert for NFT loading failures
    /// - Parameter message: Error message to display
    private func showNFTError(_ message: String) {
        let alert = UIAlertController(
            title: "NFT Error",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    /// Shows transfer input dialog for recipient address and token ID
    func showTransferInputDialog() {
        let alert = UIAlertController(
            title: "Transfer NFT",
            message: "Enter the recipient address and token ID to transfer",
            preferredStyle: .alert
        )

        // Add recipient address field
        alert.addTextField { textField in
            textField.placeholder = "Recipient Stellar Address (G...)"
            textField.keyboardType = .default
            textField.autocapitalizationType = .none
        }

        // Add token ID field
        alert.addTextField { textField in
            textField.placeholder = "Token ID"
            textField.keyboardType = .numberPad
        }

        // Cancel action
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            // No action needed
        })

        // Transfer action
        alert.addAction(UIAlertAction(title: "Transfer", style: .default) { [weak self] _ in
            guard let self = self else { return }

            let recipientAddress = alert.textFields?[0].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let tokenIdString = alert.textFields?[1].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            // Validate inputs
            guard !recipientAddress.isEmpty else {
                let errorAlert = UIAlertController(
                    title: "Invalid Input",
                    message: "Please enter a recipient address",
                    preferredStyle: .alert
                )
                errorAlert.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(errorAlert, animated: true)
                return
            }

            guard !tokenIdString.isEmpty else {
                let errorAlert = UIAlertController(
                    title: "Invalid Input",
                    message: "Please enter a token ID",
                    preferredStyle: .alert
                )
                errorAlert.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(errorAlert, animated: true)
                return
            }

            guard AppConfig.shared.validateStellarAddress(recipientAddress) else {
                let errorAlert = UIAlertController(
                    title: "Invalid Address",
                    message: "Please enter a valid Stellar address (56 characters starting with 'G')",
                    preferredStyle: .alert
                )
                errorAlert.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(errorAlert, animated: true)
                return
            }

            guard let tokenId = UInt64(tokenIdString) else {
                let errorAlert = UIAlertController(
                    title: "Invalid Token ID",
                    message: "Please enter a valid token ID (numeric value)",
                    preferredStyle: .alert
                )
                errorAlert.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(errorAlert, animated: true)
                return
            }

            // Start transfer process
            self.ResetDefaults()
            self.transferButton.isEnabled = false
            self.BeginNFCTransferSession(recipientAddress: recipientAddress, tokenId: tokenId)
        })

        present(alert, animated: true)
    }

    /// Shows input dialog for message to sign
    func showSignMessageInputDialog() {
        let alert = UIAlertController(
            title: "Sign Message",
            message: "Enter the message you want to sign with your NFC chip",
            preferredStyle: .alert
        )

        // Add message field
        alert.addTextField { textField in
            textField.placeholder = "Message to sign (hex or text)"
            textField.keyboardType = .default
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
            textField.spellCheckingType = .no
        }

        // Cancel action
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))

        // Sign action
        alert.addAction(UIAlertAction(title: "Sign", style: .default) { [weak self] _ in
            guard let self = self else { return }

            let messageText = alert.textFields?[0].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            // Validate input
            guard !messageText.isEmpty else {
                let errorAlert = UIAlertController(
                    title: "Invalid Input",
                    message: "Please enter a message to sign",
                    preferredStyle: .alert
                )
                errorAlert.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(errorAlert, animated: true)
                return
            }

            // Parse message - could be hex or text
            var messageData: Data
            if messageText.hasPrefix("0x") {
                // Hex string with 0x prefix
                let hexString = String(messageText.dropFirst(2))
                guard self.isValidHexString(hexString) && hexString.count % 2 == 0,
                      let data = Data(hexString: hexString) else {
                    let errorAlert = UIAlertController(
                        title: "Invalid Hex",
                        message: "Please enter valid hexadecimal data",
                        preferredStyle: .alert
                    )
                    errorAlert.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(errorAlert, animated: true)
                    return
                }
                messageData = data
            } else if self.isValidHexString(messageText) && messageText.count % 2 == 0 {
                // Looks like hex without 0x prefix
                guard let data = Data(hexString: messageText) else {
                    let errorAlert = UIAlertController(
                        title: "Invalid Hex",
                        message: "Please enter valid hexadecimal data",
                        preferredStyle: .alert
                    )
                    errorAlert.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(errorAlert, animated: true)
                    return
                }
                messageData = data
            } else {
                // Treat as text - UTF-8 encoding should never fail for valid strings
                guard let data = messageText.data(using: .utf8) else {
                    let errorAlert = UIAlertController(
                        title: "Invalid Message",
                        message: "Unable to encode message as UTF-8",
                        preferredStyle: .alert
                    )
                    errorAlert.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(errorAlert, animated: true)
                    return
                }
                messageData = data
            }

            // Store the message data for use in NFC operation
            self.customMessageToSign = messageData

            // Start signing process
            self.ResetDefaults()
            self.selected_keyindex = 0x01
            self.isSignOperation = true
            self.BeginNFCReadSession()
        })

        present(alert, animated: true)
    }

    // MARK: - Properties for custom message signing
    var customMessageToSign: Data?

    /// Check if string contains only valid hexadecimal characters (0-9, a-f, A-F)
    private func isValidHexString(_ string: String) -> Bool {
        let hexCharacters = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        return string.unicodeScalars.allSatisfy { hexCharacters.contains($0) }
    }
}


extension Data {
    func hexEncodedString() -> String {
        return map { String(format: "%02x", $0) }.joined()
    }
    
    init?(hexString: String) {
        let len = hexString.count / 2
        var data = Data(capacity: len)
        var i = hexString.startIndex
        for _ in 0..<len {
            let j = hexString.index(i, offsetBy: 2)
            let bytes = hexString[i..<j]
            if var num = UInt8(bytes, radix: 16) {
                data.append(&num, count: 1)
            } else {
                return nil
            }
            i = j
        }
        self = data
    }
}
