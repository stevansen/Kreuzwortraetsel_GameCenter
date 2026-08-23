import Foundation
import SQLite3

/// Dünner SQLite-Wrapper.
///
/// Bewusst kein GRDB und kein SwiftData: das Projekt hat null
/// Drittanbieter-Abhängigkeiten, Builds bleiben hermetisch, und der Katalog
/// braucht ohnehin nur Massen-Inserts und indizierte Lesevorgänge — für eine
/// ORM-Schicht gibt es hier nichts zu tun.
public final class SQLiteDatabase {
    public enum Error: Swift.Error, CustomStringConvertible {
        case open(String), prepare(String, String), step(String, String)
        public var description: String {
            switch self {
            case .open(let m): "SQLite öffnen: \(m)"
            case .prepare(let m, let sql): "SQLite prepare: \(m)\n  \(sql)"
            case .step(let m, let sql): "SQLite step: \(m)\n  \(sql)"
            }
        }
    }

    private var handle: OpaquePointer?

    public init(path: String, readOnly: Bool = false, create: Bool = true) throws {
        var flags = readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE
        if !readOnly, create { flags |= SQLITE_OPEN_CREATE }
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK else {
            let msg = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unbekannt"
            sqlite3_close(handle)
            throw Error.open("\(msg) (\(path))")
        }
        if !readOnly {
            try exec("PRAGMA journal_mode = WAL;")
            try exec("PRAGMA synchronous = NORMAL;")
        }
    }

    deinit { sqlite3_close(handle) }

    private var errorMessage: String {
        handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unbekannt"
    }

    public func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(handle, sql, nil, nil, &err) != SQLITE_OK {
            let m = err.map { String(cString: $0) } ?? errorMessage
            sqlite3_free(err)
            throw Error.step(m, sql)
        }
    }

    public func transaction<T>(_ body: () throws -> T) throws -> T {
        try exec("BEGIN")
        do {
            let r = try body()
            try exec("COMMIT")
            return r
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }

    public func prepare(_ sql: String) throws -> Statement {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw Error.prepare(errorMessage, sql)
        }
        return Statement(stmt: stmt, sql: sql, db: self)
    }

    public var lastInsertRowID: Int64 { sqlite3_last_insert_rowid(handle) }

    public final class Statement {
        private let stmt: OpaquePointer
        private let sql: String
        private weak var db: SQLiteDatabase?

        init(stmt: OpaquePointer, sql: String, db: SQLiteDatabase) {
            self.stmt = stmt; self.sql = sql; self.db = db
        }
        deinit { sqlite3_finalize(stmt) }

        public func bind(_ values: [Value]) throws {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
            for (i, v) in values.enumerated() {
                let idx = Int32(i + 1)
                switch v {
                case .null: sqlite3_bind_null(stmt, idx)
                case .int(let n): sqlite3_bind_int64(stmt, idx, n)
                case .double(let d): sqlite3_bind_double(stmt, idx, d)
                case .text(let s): sqlite3_bind_text(stmt, idx, s, -1, SQLITE_TRANSIENT)
                }
            }
        }

        /// Führt aus und verwirft das Ergebnis (INSERT/UPDATE/DDL).
        public func run(_ values: [Value] = []) throws {
            try bind(values)
            let rc = sqlite3_step(stmt)
            guard rc == SQLITE_DONE || rc == SQLITE_ROW else {
                throw Error.step(db?.errorMessage ?? "unbekannt", sql)
            }
        }

        /// Iteriert Zeilen. `body` bekommt einen Row-Accessor.
        public func query(_ values: [Value] = [], _ body: (Row) throws -> Void) throws {
            try bind(values)
            while true {
                let rc = sqlite3_step(stmt)
                if rc == SQLITE_ROW { try body(Row(stmt: stmt)) }
                else if rc == SQLITE_DONE { break }
                else { throw Error.step(db?.errorMessage ?? "unbekannt", sql) }
            }
        }
    }

    public enum Value {
        case null, int(Int64), double(Double), text(String)
        public static func int(_ n: Int) -> Value { .int(Int64(n)) }
        public static func optText(_ s: String?) -> Value { s.map { .text($0) } ?? .null }
        public static func optInt(_ n: Int?) -> Value { n.map { .int(Int64($0)) } ?? .null }
    }

    public struct Row {
        let stmt: OpaquePointer
        public func int(_ i: Int32) -> Int { Int(sqlite3_column_int64(stmt, i)) }
        public func int64(_ i: Int32) -> Int64 { sqlite3_column_int64(stmt, i) }
        public func double(_ i: Int32) -> Double { sqlite3_column_double(stmt, i) }
        public func isNull(_ i: Int32) -> Bool { sqlite3_column_type(stmt, i) == SQLITE_NULL }
        public func text(_ i: Int32) -> String {
            guard let c = sqlite3_column_text(stmt, i) else { return "" }
            return String(cString: c)
        }
        public func optText(_ i: Int32) -> String? { isNull(i) ? nil : text(i) }
        public func optInt(_ i: Int32) -> Int? { isNull(i) ? nil : int(i) }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
