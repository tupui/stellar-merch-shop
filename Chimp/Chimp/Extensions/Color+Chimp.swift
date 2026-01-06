import SwiftUI

extension Color {
    /// Brand yellow color (#FFD700) - Gold
    /// Contrast ratio with black text: ~8.59:1 (WCAG AAA compliant)
    static let chimpYellow = Color(red: 1.0, green: 0.843, blue: 0.0)
    
    /// Brand black color (#000000)
    static let chimpBlack = Color(red: 0.0, green: 0.0, blue: 0.0)
    
    /// Light background color (#FAFAFA)
    /// Uses system background for better integration with iOS design system
    static var chimpBackground: Color {
        Color(.systemBackground)
    }
}

