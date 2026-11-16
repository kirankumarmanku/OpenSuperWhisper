import SwiftUI
import UIKit

struct RecorderView: View {
    @EnvironmentObject private var dictation: DictationModel
    @EnvironmentObject private var history: DictationHistoryStore
    @State private var shownEntry: DictationEntry?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                recorder
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                List {
                    modelSection
                    historySection
                }
                .listStyle(.insetGrouped)
                // Section edges line up with the recorder card above.
                .contentMargins(.horizontal, 16, for: .scrollContent)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("OpenSuperWhisper")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $shownEntry) { entry in
                HistoryDetailView(entry: entry)
            }
        }
        .task { await dictation.prepare() }
    }

    // MARK: - Recorder

    private var recorder: some View {
        VStack(spacing: 12) {
            Text(dictation.status)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("status")

            ScrollView {
                Text(dictation.transcript.isEmpty ? "Your transcription appears here." : dictation.transcript)
                    .foregroundStyle(dictation.transcript.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)
                    .accessibilityIdentifier("transcript")
            }
            .frame(height: 132)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 12) {
                Button {
                    Task { await dictation.toggleRecording() }
                } label: {
                    Label(dictation.isRecording ? "Stop" : "Record",
                          systemImage: dictation.isRecording ? "stop.fill" : "mic.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.borderedProminent)
                .tint(dictation.isRecording ? .red : .accentColor)
                .controlSize(.large)
                .disabled(!dictation.canToggle)

                Button {
                    UIPasteboard.general.string = dictation.transcript
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .frame(minHeight: 36)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(dictation.transcript.isEmpty)
            }
        }
    }

    // MARK: - Model

    private var modelSection: some View {
        Section {
            ForEach(IOSModelCatalog.all) { model in
                modelRow(model)
            }
        } header: {
            Text("Model")
        } footer: {
            if let error = dictation.modelError {
                Text(error).foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func modelRow(_ model: IOSWhisperModel) -> some View {
        if let progress = dictation.downloadProgress[model.id] {
            HStack(spacing: 12) {
                modelLabel(model)
                Spacer()
                ProgressView(value: progress)
                    .frame(width: 64)
                Button("Cancel") { dictation.cancelDownload(model) }
                    .buttonStyle(.borderless)
            }
        } else {
            Button {
                Task { await dictation.selectModel(model) }
            } label: {
                HStack(spacing: 12) {
                    modelLabel(model)
                    Spacer()
                    if model == dictation.selectedModel {
                        Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                    } else if !dictation.isAvailable(model) {
                        Image(systemName: "arrow.down.circle").foregroundStyle(Color.accentColor)
                    }
                }
            }
            .disabled(!dictation.canChangeModel)
            .accessibilityIdentifier("model-\(model.id)")
        }
    }

    private func modelLabel(_ model: IOSWhisperModel) -> some View {
        let availability = model.isBundled ? "Built in"
            : dictation.isAvailable(model) ? "Downloaded" : "Download"
        return VStack(alignment: .leading, spacing: 2) {
            Text(model.name).foregroundStyle(Color(.label))
            // Explicit colors: a button label tints hierarchical styles with the accent color.
            Text("\(availability) · \(model.sizeMB) MB · \(model.blurb)")
                .font(.caption)
                .foregroundStyle(Color(.secondaryLabel))
        }
    }

    // MARK: - History

    private var historySection: some View {
        Section("History") {
            if history.entries.isEmpty {
                Text(history.unavailableReason.map { "History is unavailable: \($0)" }
                     ?? "No dictations yet. Each transcription is saved here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("history-empty")
            } else {
                ForEach(history.entries) { entry in
                    Button {
                        UIPasteboard.general.string = entry.text
                        shownEntry = entry
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.text)
                                .lineLimit(2)
                                .foregroundStyle(Color(.label))
                            Text("\(entry.timestamp.formatted(date: .abbreviated, time: .shortened)) · \(IOSModelCatalog.displayName(forFilename: entry.model))")
                                .font(.caption)
                                .foregroundStyle(Color(.secondaryLabel))
                        }
                    }
                }
                .onDelete { offsets in
                    for index in offsets { try? history.delete(history.entries[index]) }
                }
            }
        }
    }
}

/// The full text of a history entry; opening it has already copied the text.
struct HistoryDetailView: View {
    let entry: DictationEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Copied to the clipboard", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                    Text(entry.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                    Text("\(entry.timestamp.formatted(date: .complete, time: .shortened)) · \(IOSModelCatalog.displayName(forFilename: entry.model))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("Dictation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        UIPasteboard.general.string = entry.text
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }
            }
        }
    }
}

#Preview {
    let history = DictationHistoryStore(
        databaseURL: FileManager.default.temporaryDirectory.appendingPathComponent("preview-history.sqlite"))
    return RecorderView()
        .environmentObject(DictationModel(history: history))
        .environmentObject(history)
}
