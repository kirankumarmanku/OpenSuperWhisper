import Foundation
import GRDB

/// One saved transcription.
struct DictationEntry: Identifiable, Codable, Equatable, FetchableRecord, PersistableRecord {
    let id: UUID
    let timestamp: Date
    let text: String
    /// The model file that produced it, e.g. "ggml-tiny.en.bin".
    let model: String

    static let databaseTableName = "dictations"

    enum Columns {
        static let timestamp = Column(CodingKeys.timestamp)
    }
}

/// Transcription history on iOS, in the macOS RecordingStore's style (GRDB, a DatabaseMigrator,
/// a database under Application Support/<bundle id>/). A separate store because RecordingStore is
/// tied to the macOS recorder and keeps no record of the model used.
@MainActor
final class DictationHistoryStore: ObservableObject {
    @Published private(set) var entries: [DictationEntry] = []
    /// Set when the database could not be opened; the app keeps working without history.
    private(set) var unavailableReason: String?

    private let dbQueue: DatabaseQueue?

    nonisolated static var defaultDatabaseURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "OpenSuperWhisperiOS")
            .appendingPathComponent("history.sqlite")
    }

    init(databaseURL: URL = DictationHistoryStore.defaultDatabaseURL) {
        do {
            try FileManager.default.createDirectory(at: databaseURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let queue = try DatabaseQueue(path: databaseURL.path)
            try Self.migrator.migrate(queue)
            dbQueue = queue
        } catch {
            dbQueue = nil
            unavailableReason = error.localizedDescription
        }
        reload()
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: DictationEntry.databaseTableName) { t in
                t.column("id", .text).primaryKey()
                t.column("timestamp", .datetime).notNull().indexed()
                t.column("text", .text).notNull()
                t.column("model", .text).notNull()
            }
        }
        return migrator
    }

    /// Save a transcription; the newest entry is shown first.
    @discardableResult
    func add(text: String, model: String, at timestamp: Date = Date()) throws -> DictationEntry {
        let entry = DictationEntry(id: UUID(), timestamp: timestamp, text: text, model: model)
        try database().write { db in try entry.insert(db) }
        reload()
        return entry
    }

    func delete(_ entry: DictationEntry) throws {
        _ = try database().write { db in try entry.delete(db) }
        reload()
    }

    func reload() {
        guard let dbQueue else { entries = []; return }
        entries = (try? dbQueue.read { db in
            try DictationEntry.order(DictationEntry.Columns.timestamp.desc).fetchAll(db)
        }) ?? []
    }

    private func database() throws -> DatabaseQueue {
        guard let dbQueue else {
            throw NSError(domain: "DictationHistoryStore", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "History is unavailable: \(unavailableReason ?? "unknown error")"])
        }
        return dbQueue
    }
}
