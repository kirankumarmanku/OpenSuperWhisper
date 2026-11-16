import SwiftUI
import UIKit

struct RecorderView: View {
    @EnvironmentObject private var dictation: DictationModel

    private var isRecording: Bool { dictation.phase == .recording }

    var body: some View {
        VStack(spacing: 20) {
            Text(dictation.status)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("status")

            ScrollView {
                Text(dictation.transcript.isEmpty ? "Your transcription appears here." : dictation.transcript)
                    .foregroundStyle(dictation.transcript.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("transcript")
            }
            .padding()
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))

            Button {
                Task { await dictation.toggleRecording() }
            } label: {
                Label(isRecording ? "Stop" : "Record",
                      systemImage: isRecording ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.title2.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.borderedProminent)
            .tint(isRecording ? .red : .accentColor)
            .disabled(!dictation.canToggle)

            Button {
                UIPasteboard.general.string = dictation.transcript
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(dictation.transcript.isEmpty)
        }
        .padding()
        .task { await dictation.prepare() }
    }
}

#Preview {
    RecorderView().environmentObject(DictationModel())
}
