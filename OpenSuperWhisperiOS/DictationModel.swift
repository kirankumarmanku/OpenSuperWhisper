import Foundation

/// Record, then transcribe on device with the bundled ggml-tiny.en model.
@MainActor
final class DictationModel: ObservableObject {
    enum Phase: Equatable {
        case loadingModel, ready, recording, transcribing
        case failed(String)
    }

    @Published private(set) var phase: Phase = .loadingModel
    @Published private(set) var transcript = ""

    private let recorder = IOSAudioRecorder()
    private var service: TranscriptionService?

    var status: String {
        switch phase {
        case .loadingModel: return "Loading model…"
        case .ready: return transcript.isEmpty ? "Ready. Tap Record to dictate." : "Done."
        case .recording: return "Recording… tap Stop when you're done."
        case .transcribing: return "Transcribing…"
        case .failed(let message): return message
        }
    }

    var canToggle: Bool { phase == .ready || phase == .recording || isFailedAfterLoad }
    private var isFailedAfterLoad: Bool {
        if case .failed = phase { return service != nil }
        return false
    }

    /// The bundled tiny English model, copied once into Application Support by the shared
    /// model manager (the same place the macOS app keeps its models).
    static func bundledModelPath() -> String {
        let manager = WhisperModelManager.shared
        manager.ensureDefaultModelPresent()
        return manager.modelsDirectory.appendingPathComponent("ggml-tiny.en.bin").path
    }

    static func englishSettings() -> Settings {
        var settings = Settings()
        settings.selectedLanguage = "en"   // ggml-tiny.en is English-only
        return settings
    }

    func prepare() async {
        guard service == nil else { return }
        let selection = TranscriptionService.EngineSelection(
            engine: "whisper", modelPath: Self.bundledModelPath(), modelVersion: "v3")
        let service = TranscriptionService(selection: selection)
        do {
            try await service.waitUntilReady()
            self.service = service
            phase = .ready
        } catch {
            phase = .failed("Could not load the model: \(service.loadingError ?? error.localizedDescription)")
        }
    }

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
            transcript = text
            phase = .ready
        } catch {
            recorder.cancel()
            phase = .failed("Transcription failed: \(error.localizedDescription)")
        }
    }
}
