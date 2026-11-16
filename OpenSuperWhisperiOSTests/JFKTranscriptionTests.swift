import XCTest
@testable import OpenSuperWhisperiOS

/// End to end on iOS: the bundled ggml-tiny.en model, loaded through the shared model manager and
/// TranscriptionService exactly as the app does, transcribes the JFK sample.
@MainActor
final class JFKTranscriptionTests: XCTestCase {
    func testBundledTinyModelTranscribesJFK() async throws {
        let wav = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "jfk", withExtension: "wav"))
        let selection = TranscriptionService.EngineSelection(
            engine: "whisper", modelPath: DictationModel.bundledModelPath(), modelVersion: "v3")
        let service = TranscriptionService(selection: selection)
        try await service.waitUntilReady()

        let text = try await service.transcribeAudio(url: wav, settings: DictationModel.englishSettings())
        print("JFK_TRANSCRIPT: \(text)")

        let normalized = text.lowercased()
            .components(separatedBy: CharacterSet.letters.union(.whitespaces).inverted).joined()
            .split(separator: " ").joined(separator: " ")
        XCTAssertTrue(normalized.contains("ask not what your country can do for you"),
                      "transcript was: \(text)")
    }
}
