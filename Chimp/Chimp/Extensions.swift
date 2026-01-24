import Foundation
import SwiftUI

// MARK: - Data Extensions

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
            if let num = UInt8(bytes, radix: 16) {
                data.append(num)
            } else {
                return nil
            }
            i = j
        }
        self = data
    }
}

// MARK: - Color Extensions

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
