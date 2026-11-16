import SwiftUI

@main
struct OpenSuperWhisperiOSApp: App {
    @StateObject private var dictation = DictationModel()

    var body: some Scene {
        WindowGroup {
            RecorderView()
                .environmentObject(dictation)
        }
    }
}
