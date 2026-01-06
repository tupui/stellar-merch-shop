import SwiftUI
import UIKit

struct ConfettiOverlay: View {
    let message: String
    
    var body: some View {
        ZStack {
            // Confetti animation
            ConfettiOverlayView()
            
            // Success message
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.green)
                
                Text(message)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .padding(.vertical, 40)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.systemBackground))
                    .shadow(color: Color.black.opacity(0.2), radius: 20, x: 0, y: 10)
            )
            .padding(.horizontal, 40)
            .transition(.scale.combined(with: .opacity))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.3))
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
        // No updates needed
    }
}

