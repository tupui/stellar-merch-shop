import SwiftUI

@main
struct ChimpApp: App {
    var body: some Scene {
        WindowGroup {
            MainView()
                .preferredColorScheme(.light) // Force light mode for brand consistency
        }
    }
}
