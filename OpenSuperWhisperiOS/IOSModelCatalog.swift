import Foundation

/// The Whisper models the iOS app offers. Tiny ships in the app bundle; Base is downloaded on
/// demand through the shared WhisperModelManager into the same models directory.
struct IOSWhisperModel: Identifiable, Equatable {
    /// The model file's name in the models directory; also what history records as "model used".
    let filename: String
    let name: String
    let sizeMB: Int
    let blurb: String
    /// Nil for the bundled model.
    let downloadURL: URL?

    var id: String { filename }
    var isBundled: Bool { downloadURL == nil }
}

enum IOSModelCatalog {
    static let tinyEn = IOSWhisperModel(
        filename: "ggml-tiny.en.bin", name: "Tiny (English)",
        sizeMB: 78, blurb: "fastest", downloadURL: nil)
    static let baseEn = IOSWhisperModel(
        filename: "ggml-base.en.bin", name: "Base (English)",
        sizeMB: 148, blurb: "more accurate",
        downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin")!)

    static let all = [tinyEn, baseEn]
    static let defaultModel = tinyEn

    static func model(filename: String) -> IOSWhisperModel? {
        all.first { $0.filename == filename }
    }

    /// The name history shows for a recorded model file, falling back to the file name for models
    /// no longer in the catalog.
    static func displayName(forFilename filename: String) -> String {
        model(filename: filename)?.name ?? filename
    }
}

/// The user's model choice, kept across launches. Stored as the model's file name rather than a
/// path: an iOS app's container path can change between installs and updates.
struct IOSModelPreference {
    static let key = "ios.selectedWhisperModel"
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The saved choice, if it names a model in the catalog.
    var savedModel: IOSWhisperModel? {
        defaults.string(forKey: Self.key).flatMap(IOSModelCatalog.model(filename:))
    }

    func save(_ model: IOSWhisperModel) {
        defaults.set(model.filename, forKey: Self.key)
    }
}
