import Foundation
import CSQLite

public enum StoreError: Error, LocalizedError {
    case database(String), invalid(String), unsupportedVersion
    public var errorDescription: String? {
        switch self { case .database(let s), .invalid(let s): return s; case .unsupportedVersion: return "This database was created by a newer app." }
    }
}
// Confined to MainActor: no SQLite connection is shared across executors.
@MainActor
public final class Database {
    private var handle: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    public init(path: String) throws {
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Cannot open database"
            sqlite3_close(handle); handle = nil; throw StoreError.database(message)
        }
        sqlite3_busy_timeout(handle, 3000)
        try execute("PRAGMA foreign_keys=ON")
        try execute("PRAGMA journal_mode=WAL")
        let version = Int(try query("PRAGMA user_version").first?["user_version"] ?? "0") ?? 0
        guard version <= 1 else { throw StoreError.unsupportedVersion }
        if version == 0 {
            guard let url = Bundle.module.url(forResource: "001_initial", withExtension: "sql", subdirectory: "migrations") else { throw StoreError.database("Missing migration") }
            let sql = try String(contentsOf: url, encoding: .utf8)
            try transaction { try executeScript(sql); try execute("PRAGMA user_version=1") }
        }
    }
    isolated deinit { sqlite3_close(handle) }
    private func prepare(_ sql: String, _ values: [String?]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw failure() }
        for (offset, value) in values.enumerated() {
            let result = value.map { sqlite3_bind_text(statement, Int32(offset+1), $0, -1, transient) } ?? sqlite3_bind_null(statement, Int32(offset+1))
            if result != SQLITE_OK { sqlite3_finalize(statement); throw failure() }
        }
        return statement
    }
    private func failure() -> StoreError { .database(String(cString: sqlite3_errmsg(handle))) }
    private func executeScript(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }
    }
    public func execute(_ sql: String, _ values: [String?] = []) throws {
        let s = try prepare(sql, values); defer { sqlite3_finalize(s) }
        let result = sqlite3_step(s)
        guard result == SQLITE_DONE || result == SQLITE_ROW else { throw failure() }
    }
    public func query(_ sql: String, _ values: [String?] = []) throws -> [[String: String]] {
        let s = try prepare(sql, values); defer { sqlite3_finalize(s) }
        var rows: [[String: String]] = []
        while true {
            let result = sqlite3_step(s)
            if result == SQLITE_DONE { return rows }
            guard result == SQLITE_ROW else { throw failure() }
            var row: [String: String] = [:]
            for i in 0..<sqlite3_column_count(s) {
                if let text = sqlite3_column_text(s, i) { row[String(cString: sqlite3_column_name(s, i))] = String(cString: text) }
            }
            rows.append(row)
        }
    }
    public func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do { let result = try body(); try execute("COMMIT"); return result }
        catch { try? execute("ROLLBACK"); throw error }
    }
}
