//
//  ContentView.swift
//  VisionProMixedHello
//
//  Created by Tatsuya Ogawa on 2024/10/30.
//

import SwiftUI
import RealityKit

struct ContentView: View {

    var body: some View {
        VStack {
            WebRTCView()
        }
        .padding()
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environment(AppModel())
}
