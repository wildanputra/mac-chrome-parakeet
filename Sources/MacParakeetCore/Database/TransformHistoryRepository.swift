import Foundation
import GRDB

public protocol TransformHistoryRepositoryProtocol: Sendable {
    func save(_ entry: TransformHistoryEntry) throws
    func fetchAll() throws -> [TransformHistoryEntry]
    func fetchRecent(limit: Int) throws -> [TransformHistoryEntry]
    /// Atomic `(recent rows, total count)` read so the UI's "showing N of M"
    /// footer is consistent with the visible rows. Splitting into two reads
    /// can interleave with a concurrent write and produce mismatched values.
    func fetchRecentWithCount(limit: Int) throws -> (entries: [TransformHistoryEntry], totalCount: Int)
    func fetch(id: UUID) throws -> TransformHistoryEntry?
    func fetch(idPrefix: String) throws -> [TransformHistoryEntry]
    func count() throws -> Int
    func delete(id: UUID) throws -> Bool
    func deleteAll() throws
}

public final class TransformHistoryRepository: TransformHistoryRepositoryProtocol {
    private let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public func save(_ entry: TransformHistoryEntry) throws {
        try dbQueue.write { db in
            try entry.save(db)
        }
    }

    public func fetchAll() throws -> [TransformHistoryEntry] {
        try dbQueue.read { db in
            try TransformHistoryEntry
                .order(TransformHistoryEntry.Columns.createdAt.desc)
                .fetchAll(db)
        }
    }

    public func fetchRecent(limit: Int = 200) throws -> [TransformHistoryEntry] {
        try dbQueue.read { db in
            try TransformHistoryEntry
                .order(TransformHistoryEntry.Columns.createdAt.desc)
                .limit(max(0, limit))
                .fetchAll(db)
        }
    }

    public func fetchRecentWithCount(
        limit: Int = 200
    ) throws -> (entries: [TransformHistoryEntry], totalCount: Int) {
        try dbQueue.read { db in
            let entries = try TransformHistoryEntry
                .order(TransformHistoryEntry.Columns.createdAt.desc)
                .limit(max(0, limit))
                .fetchAll(db)
            let totalCount = try TransformHistoryEntry.fetchCount(db)
            return (entries, totalCount)
        }
    }

    public func fetch(id: UUID) throws -> TransformHistoryEntry? {
        try dbQueue.read { db in
            try TransformHistoryEntry.fetchOne(db, key: id)
        }
    }

    public func fetch(idPrefix: String) throws -> [TransformHistoryEntry] {
        // GRDB's `PersistableRecord` writes a Codable `UUID` as a 16-byte
        // BLOB into the `.text`-affinity `id` column (SQLite's type system
        // is dynamic). `hex(id)` returns the lowercase hex of those bytes
        // — that's the branch that matches a hex prefix. The `replace(...)`
        // branch handles the (rare) case where a row was written as a
        // TEXT UUID string by another path. Both branches present so the
        // lookup keeps working if GRDB's storage encoding ever shifts.
        let escapedPrefix = Self.escapeLikePattern(
            idPrefix
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: "-", with: "")
        )
        guard !escapedPrefix.isEmpty else { return [] }
        let pattern = "\(escapedPrefix)%"

        return try dbQueue.read { db in
            try TransformHistoryEntry
                .filter(
                    sql: """
                        (lower(hex(id)) LIKE ? ESCAPE '\\'
                            OR replace(lower(id), '-', '') LIKE ? ESCAPE '\\')
                        """,
                    arguments: StatementArguments([pattern, pattern])
                )
                .order(TransformHistoryEntry.Columns.createdAt.desc)
                .fetchAll(db)
        }
    }

    public func count() throws -> Int {
        try dbQueue.read { db in
            try TransformHistoryEntry.fetchCount(db)
        }
    }

    public func delete(id: UUID) throws -> Bool {
        try dbQueue.write { db in
            if try TransformHistoryEntry.deleteOne(db, key: id) {
                return true
            }
            // Historical/prerelease rows may have TEXT UUID primary keys,
            // while GRDB persists new UUID keys as BLOBs. Prefix lookup can
            // surface either form, so delete needs the same legacy fallback.
            try db.execute(
                sql: "DELETE FROM transform_history WHERE lower(id) = ?",
                arguments: [id.uuidString.lowercased()]
            )
            return db.changesCount > 0
        }
    }

    public func deleteAll() throws {
        _ = try dbQueue.write { db in
            try TransformHistoryEntry.deleteAll(db)
        }
    }

    private static func escapeLikePattern(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }
}
