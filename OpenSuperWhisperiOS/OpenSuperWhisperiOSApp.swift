import SwiftUI

@main
struct OpenSuperWhisperiOSApp: App {
    @StateObject private var history: DictationHistoryStore
    @StateObject private var dictation: DictationModel

    init() {
        let history = DictationHistoryStore()
        _history = StateObject(wrappedValue: history)
        _dictation = StateObject(wrappedValue: DictationModel(history: history))
    }

    var body: some Scene {
        WindowGroup {
            RecorderView()
                .environmentObject(dictation)
                .environmentObject(history)
        }
    }
}
