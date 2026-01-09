import SwiftUI
import UIKit

struct ConfettiOverlay: View {
    var body: some View {
        ZStack {
            // Confetti animation only - success message shown in NFC session
            ConfettiOverlayView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}

struct ConfettiOverlayView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let containerView = UIView()
        containerView.backgroundColor = .clear
        
        // Add confetti view
        let confettiView = ConfettiView(frame: containerView.bounds)
        confettiView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        containerView.addSubview(confettiView)
        
        // Start confetti animation
        DispatchQueue.main.async {
            confettiView.startConfetti()
        }
        
        return containerView
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
    }
}

