//
//  ContentView.swift
//  Chimp
//
//  Created by Pamphile Roy on 11.12.25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        ViewControllerWrapper()
    }
}

struct ViewControllerWrapper: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> ViewController {
        return ViewController()
    }
    
    func updateUIViewController(_ uiViewController: ViewController, context: Context) {
        // No updates needed
    }
}

#Preview {
    ContentView()
}
