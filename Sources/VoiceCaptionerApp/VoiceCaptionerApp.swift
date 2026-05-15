import SwiftUI
import VoiceCaptionerAppModel

@main
struct VoiceCaptionerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: VoiceCaptionerAppModel())
        }
        .windowStyle(.titleBar)
    }
}
