import Foundation

/// Record, then transcribe on device with the chosen Whisper model, and keep a history.
@MainActor
final class DictationModel: ObservableObject {
    enum Phase: Equatable {
        case loadingModel, ready, recording, transcribing
        case failed(String)
    }

    @Published private(set) var phase: Phase = .loadingModel
    @Published private(set) var transcript = ""
    @Published private(set) var selectedModel: IOSWhisperModel
    /// Download progress (0...1) per model file, present only while that model is downloading.
    @Published private(set) var downloadProgress: [String: Double] = [:]
    @Published private(set) var modelError: String?

    let history: DictationHistoryStore
    private let preferences: IOSModelPreference
    private let modelManager = WhisperModelManager.shared
    private let recorder = IOSAudioRecorder()
    private var service: TranscriptionService?

    init(history: DictationHistoryStore, preferences: IOSModelPreference = IOSModelPreference()) {
        self.history = history
        self.preferences = preferences
        // A downloaded model can disappear (storage cleanup, reinstall): fall back to the built-in one.
        if let saved = preferences.savedModel,
           saved.isBundled || WhisperModelManager.shared.isModelDownloaded(name: saved.filename) {
            selectedModel = saved
        } else {
            selectedModel = IOSModelCatalog.defaultModel
        }
    }

    var status: String {
        switch phase {
        case .loadingModel: return "Loading \(selectedModel.name)…"
        case .ready: return transcript.isEmpty ? "Ready. Tap Record to dictate." : "Done."
        case .recording: return "Recording… tap Stop when you're done."
        case .transcribing: return "Transcribing…"
        case .failed(let message): return message
        }
    }

    var isRecording: Bool { phase == .recording }

    var canToggle: Bool { phase == .ready || phase == .recording || isFailedAfterLoad }

    /// Switching models is allowed whenever no recording or transcription is in progress.
    var canChangeModel: Bool { phase != .recording && phase != .transcribing && phase != .loadingModel }

    private var isFailedAfterLoad: Bool {
        if case .failed = phase { return service != nil }
        return false
    }

    // MARK: - Models

    /// The bundled tiny English model, copied once into Application Support by the shared
    /// model manager (the same place the macOS app keeps its models).
    static func bundledModelPath() -> String {
        let manager = WhisperModelManager.shared
        manager.ensureDefaultModelPresent()
        return manager.modelsDirectory.appendingPathComponent(IOSModelCatalog.tinyEn.filename).path
    }

    static func englishSettings() -> Settings {
        var settings = Settings()
        settings.selectedLanguage = "en"   // both catalog models are English-only
        return settings
    }

    func isAvailable(_ model: IOSWhisperModel) -> Bool {
        model.isBundled || modelManager.isModelDownloaded(name: model.filename)
    }

    private func path(for model: IOSWhisperModel) -> String {
        model.isBundled ? Self.bundledModelPath()
                        : modelManager.modelsDirectory.appendingPathComponent(model.filename).path
    }

    private func selection(for model: IOSWhisperModel) -> TranscriptionService.EngineSelection {
        .init(engine: "whisper", modelPath: path(for: model), modelVersion: "v3")
    }

    func prepare() async {
        guard service == nil else { return }
        let service = TranscriptionService(selection: selection(for: selectedModel))
        self.service = service
        await waitForEngine(service)
    }

    /// Use `model` from now on, downloading it first if needed. The choice persists across launches.
    func selectModel(_ model: IOSWhisperModel) async {
        guard canChangeModel, model != selectedModel, downloadProgress[model.id] == nil else { return }
        modelError = nil
        if !isAvailable(model) {
            guard await download(model) else { return }
        }
        selectedModel = model
        preferences.save(model)
        guard let service else { return }
        phase = .loadingModel
        service.loadEngine(selection: selection(for: model))
        await waitForEngine(service)
    }

    func cancelDownload(_ model: IOSWhisperModel) {
        modelManager.cancelDownload(name: model.filename)
    }

    private func download(_ model: IOSWhisperModel) async -> Bool {
        guard let url = model.downloadURL else { return false }
        downloadProgress[model.id] = 0
        defer { downloadProgress[model.id] = nil }
        do {
            try await modelManager.downloadModel(url: url, name: model.filename) { [weak self] fraction in
                Task { @MainActor in
                    guard let self, self.downloadProgress[model.id] != nil else { return }
                    self.downloadProgress[model.id] = fraction
                }
            }
            return true
        } catch is CancellationError {
            return false
        } catch {
            modelError = "Could not download \(model.name): \(error.localizedDescription)"
            return false
        }
    }

    private func waitForEngine(_ service: TranscriptionService) async {
        do {
            try await service.waitUntilReady()
            phase = .ready
        } catch {
            phase = .failed("Could not load \(selectedModel.name): \(service.loadingError ?? error.localizedDescription)")
        }
    }

    // MARK: - Recording

    func toggleRecording() async {
        if recorder.isRecording {
            await stopAndTranscribe()
        } else {
            await startRecording()
        }
    }

    private func startRecording() async {
        guard await IOSAudioRecorder.requestPermission() else {
            phase = .failed("Microphone access is off. Turn it on in Settings > Privacy > Microphone.")
            return
        }
        do {
            try recorder.start()
            phase = .recording
        } catch {
            phase = .failed("Could not start recording: \(error.localizedDescription)")
        }
    }

    private func stopAndTranscribe() async {
        guard let service else { return }
        do {
            let audio = try recorder.stop()
            phase = .transcribing
            let text = try await service.transcribeAudio(
                url: audio.url, settings: Self.englishSettings(), pcmSamples: audio.samples)
            try? FileManager.default.removeItem(at: audio.url)
            finishTranscription(text)
        } catch {
            recorder.cancel()
            phase = .failed("Transcription failed: \(error.localizedDescription)")
        }
    }

    /// Show a finished transcription and save it to history (empty results are not saved).
    func finishTranscription(_ text: String) {
        transcript = text
        phase = .ready
        guard !text.isEmpty else { return }
        do {
            try history.add(text: text, model: selectedModel.filename)
        } catch {
            phase = .failed("Transcribed, but not saved to history: \(error.localizedDescription)")
        }
    }
}
