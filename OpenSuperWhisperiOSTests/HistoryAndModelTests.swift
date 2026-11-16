import XCTest
@testable import OpenSuperWhisperiOS

@MainActor
final class HistoryAndModelTests: XCTestCase {
    private var tempDir: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("osw-tests-\(UUID().uuidString)")
        suiteName = "osw-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeStore() -> DictationHistoryStore {
        DictationHistoryStore(databaseURL: tempDir.appendingPathComponent("history.sqlite"))
    }

    func testHistoryKeepsNewestFirstAndPersists() throws {
        let store = makeStore()
        XCTAssertNil(store.unavailableReason)
        XCTAssertTrue(store.entries.isEmpty)
        try store.add(text: "first", model: "ggml-tiny.en.bin", at: Date(timeIntervalSince1970: 100))
        try store.add(text: "second", model: "ggml-base.en.bin", at: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(store.entries.map(\.text), ["second", "first"])

        let reopened = makeStore()
        XCTAssertEqual(reopened.entries.map(\.text), ["second", "first"])
        XCTAssertEqual(reopened.entries.map(\.model), ["ggml-base.en.bin", "ggml-tiny.en.bin"])
        XCTAssertEqual(reopened.entries.first?.timestamp, Date(timeIntervalSince1970: 200))

        try reopened.delete(reopened.entries[0])
        XCTAssertEqual(makeStore().entries.map(\.text), ["first"])
    }

    func testFinishedTranscriptionIsSavedWithItsModel() {
        let history = makeStore()
        let model = DictationModel(history: history, preferences: IOSModelPreference(defaults: defaults))
        model.finishTranscription("ask not what your country can do for you")
        XCTAssertEqual(model.transcript, "ask not what your country can do for you")
        XCTAssertEqual(history.entries.map(\.text), ["ask not what your country can do for you"])
        XCTAssertEqual(history.entries.first?.model, IOSModelCatalog.tinyEn.filename)

        model.finishTranscription("")
        XCTAssertEqual(history.entries.count, 1, "an empty transcription is not saved")
    }

    func testModelChoicePersistsAndFallsBackWhenUnavailable() {
        let preferences = IOSModelPreference(defaults: defaults)
        XCTAssertNil(preferences.savedModel)
        XCTAssertEqual(DictationModel(history: makeStore(), preferences: preferences).selectedModel,
                       IOSModelCatalog.defaultModel, "tiny.en is the default")

        preferences.save(IOSModelCatalog.baseEn)
        XCTAssertEqual(IOSModelPreference(defaults: defaults).savedModel, IOSModelCatalog.baseEn)
        let baseDownloaded = WhisperModelManager.shared.isModelDownloaded(name: IOSModelCatalog.baseEn.filename)
        XCTAssertEqual(DictationModel(history: makeStore(), preferences: preferences).selectedModel,
                       baseDownloaded ? IOSModelCatalog.baseEn : IOSModelCatalog.tinyEn,
                       "a saved model that is not on disk falls back to the built-in one")

        defaults.set("ggml-gone.bin", forKey: IOSModelPreference.key)
        XCTAssertNil(IOSModelPreference(defaults: defaults).savedModel)
    }

    /// Downloads ggml-base.en (148 MB) through the picker path, then transcribes the JFK sample with
    /// it. Opt-in: run with TEST_RUNNER_OSW_RUN_DOWNLOAD_TESTS=1 in xcodebuild's environment.
    func testSelectingBaseDownloadsItAndTranscribesJFK() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["OSW_RUN_DOWNLOAD_TESTS"] == "1",
                          "set TEST_RUNNER_OSW_RUN_DOWNLOAD_TESTS=1 to download ggml-base.en")
        let preferences = IOSModelPreference(defaults: defaults)
        let model = DictationModel(history: makeStore(), preferences: preferences)
        await model.prepare()
        await model.selectModel(IOSModelCatalog.baseEn)
        XCTAssertNil(model.modelError)
        XCTAssertEqual(model.selectedModel, IOSModelCatalog.baseEn)
        XCTAssertEqual(model.phase, .ready)
        XCTAssertEqual(IOSModelPreference(defaults: defaults).savedModel, IOSModelCatalog.baseEn)

        let wav = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "jfk", withExtension: "wav"))
        let basePath = WhisperModelManager.shared.modelsDirectory
            .appendingPathComponent(IOSModelCatalog.baseEn.filename).path
        let service = TranscriptionService(selection: .init(engine: "whisper", modelPath: basePath, modelVersion: "v3"))
        try await service.waitUntilReady()
        let text = try await service.transcribeAudio(url: wav, settings: DictationModel.englishSettings())
        print("JFK_TRANSCRIPT_BASE: \(text)")
        XCTAssertTrue(text.lowercased().contains("ask not what your country can do for you"), text)
    }
}
