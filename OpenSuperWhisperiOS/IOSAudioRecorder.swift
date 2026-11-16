import AVFoundation

/// Microphone capture on iOS: the audio session and permission around the shared
/// `PCMRecordingSession`, which writes the 16 kHz mono file and samples the engines take.
final class IOSAudioRecorder {
    private var session: PCMRecordingSession?

    var isRecording: Bool { session != nil }

    static func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func start() throws {
        // The input node only reports a usable format once a record-capable session is active.
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
        try audio.setActive(true)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dictation-\(UUID().uuidString).wav")
        let recording = try PCMRecordingSession(url: url)
        try recording.start()
        session = recording
    }

    func stop() throws -> RecordedAudio {
        guard let recording = session else { throw TranscriptionError.audioConversionFailed }
        session = nil
        defer { deactivate() }
        return try recording.finish()
    }

    func cancel() {
        session?.cancel()
        session = nil
        deactivate()
    }

    private func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
