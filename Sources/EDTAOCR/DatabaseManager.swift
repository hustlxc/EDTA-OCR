import SQLite3
import Foundation

class DatabaseManager {
    private var db: OpaquePointer?

    init() {
        // Use current working directory (where user launches from)
        let dbDir = FileManager.default.currentDirectoryPath
        let dbPath = "\(dbDir)/edta_ocr.db"
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("Failed to open database: \(String(cString: sqlite3_errmsg(db)))")
            db = nil
            return
        }
        createTable()
    }

    deinit {
        if let db = db { sqlite3_close(db) }
    }

    private func createTable() {
        let sql = """
        CREATE TABLE IF NOT EXISTS records (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            姓名 TEXT DEFAULT '',
            性别 TEXT DEFAULT '',
            年龄 TEXT DEFAULT '',
            流水号 TEXT DEFAULT '',
            采血时间 TEXT DEFAULT '',
            科室 TEXT DEFAULT '',
            床号 TEXT DEFAULT '',
            录入时间 TEXT DEFAULT (datetime('now','localtime'))
        );
        CREATE INDEX IF NOT EXISTS idx_serial ON records(流水号);
        CREATE INDEX IF NOT EXISTS idx_time ON records(录入时间);
        """
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            print("Failed to create table: \(String(cString: sqlite3_errmsg(db)))")
        }
    }

    func insert(name: String, gender: String, age: String, serialNumber: String,
                collectionTime: String, department: String, bedNumber: String) -> Bool {
        guard let db = db else { return false }
        let sql = """
        INSERT INTO records (姓名, 性别, 年龄, 流水号, 采血时间, 科室, 床号)
        VALUES (?, ?, ?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (name as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (gender as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (age as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 4, (serialNumber as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 5, (collectionTime as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 6, (department as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 7, (bedNumber as NSString).utf8String, -1, nil)

        return sqlite3_step(stmt) == SQLITE_DONE
    }

    func fetchRecent(limit: Int = 100) -> [Record] {
        guard let db = db else { return [] }
        let sql = "SELECT * FROM records ORDER BY id DESC LIMIT ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int(stmt, 1, Int32(limit))

        var records: [Record] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            records.append(Record(
                id: Int(sqlite3_column_int(stmt, 0)),
                name: cstring(stmt, 1),
                gender: cstring(stmt, 2),
                age: cstring(stmt, 3),
                serialNumber: cstring(stmt, 4),
                collectionTime: cstring(stmt, 5),
                department: cstring(stmt, 6),
                bedNumber: cstring(stmt, 7),
                savedAt: cstring(stmt, 8)
            ))
        }
        return records
    }

    func count() -> Int {
        guard let db = db else { return 0 }
        let sql = "SELECT COUNT(*) FROM records;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(sqlite3_column_int(stmt, 0))
        }
        return 0
    }

    private func cstring(_ stmt: OpaquePointer?, _ col: Int32) -> String {
        guard let stmt = stmt, let ptr = sqlite3_column_text(stmt, col) else { return "" }
        return String(cString: ptr)
    }
}
