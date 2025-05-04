//
//  VisionProHelloApp.swift
//  VisionProHello
//
//  Created by Tatsuya Ogawa on 2024/10/26.
//

import SwiftUI

@main
struct VisionProApp: App {
    @State private var appModel = AppModel()
    @State private var webRTCViewModel = WebRTCViewModel()
    var body: some Scene {
        WindowGroup {
            VStack{
                ContentView().environment(webRTCViewModel)
                ToggleImmersiveSpaceButton().environment(appModel)
            }
        }
        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            ImmersiveView()
                .environment(appModel)
                .onAppear {
                    appModel.immersiveSpaceState = .open
                    Task{
                        await webRTCViewModel.startLocalVideoCapture()
                    }
                }
                .onDisappear {
                    appModel.immersiveSpaceState = .closed
                }
        }.immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
