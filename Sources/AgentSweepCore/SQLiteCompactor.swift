import Foundation
import SQLite3

public struct DBStats: Sendable, Hashable {
    public let fileBytes: Int64
    public let walBytes: Int64
    public let pageSize: Int64
    public let pageCount: Int64
    public let freePages: Int64

    /// Space VACUUM is guaranteed to give back; fragmentation usually adds more.
    public var reclaimable: Int64 { freePages * pageSize + walBytes }
}

public struct CompactResult: Sendable {
    public let before: Int64
    public let after: Int64
    public let backup: String
}

public enum SQLiteError: LocalizedError {
    case open(String), exec(String), noSpace(needed: Int64)

    public var errorDescription: String? {
        switch self {
        case .open(let m): return "无法打开数据库：\(m)"
        case .exec(let m): return "压缩失败：\(m)"
        case .noSpace(let n): return "磁盘空间不足，备份需要 \(ByteFormat.string(n))"
        }
    }
}

public enum SQLiteCompactor {
    static func size(_ p: String) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: p))?[.size] as? NSNumber)?.int64Value ?? 0
    }

    public static func stats(_ path: String) throws -> DBStats {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            defer { sqlite3_close(db) }
            throw SQLiteError.open(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_close(db) }
        func pragma(_ name: String) -> Int64 {
            var st: OpaquePointer?
            defer { sqlite3_finalize(st) }
            guard sqlite3_prepare_v2(db, "PRAGMA \(name)", -1, &st, nil) == SQLITE_OK, sqlite3_step(st) == SQLITE_ROW else { return 0 }
            return sqlite3_column_int64(st, 0)
        }
        return DBStats(fileBytes: size(path), walBytes: size(path + "-wal"),
                       pageSize: pragma("page_size"), pageCount: pragma("page_count"), freePages: pragma("freelist_count"))
    }

    /// Backs the database up, then checkpoints the WAL and runs VACUUM. The owning app must not be running.
    public static func compact(_ path: String, backupDir: URL = AppPaths.support.appendingPathComponent("backups")) throws -> CompactResult {
        let fm = FileManager.default
        let before = size(path) + size(path + "-wal")
        let free = (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage ?? .max
        // Backup plus VACUUM's temporary copy.
        guard free > before * 2 else { throw SQLiteError.noSpace(needed: before * 2) }

        try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backup = backupDir.appendingPathComponent("\(stamp)-\((path as NSString).lastPathComponent)").path
        try fm.copyItem(atPath: path, toPath: backup)
        for ext in ["-wal", "-shm"] where fm.fileExists(atPath: path + ext) {
            try fm.copyItem(atPath: path + ext, toPath: backup + ext)
        }

        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            defer { sqlite3_close(db) }
            throw SQLiteError.open(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 3000)
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE); VACUUM;", nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "未知错误"
            sqlite3_free(err)
            throw SQLiteError.exec(msg)
        }
        return CompactResult(before: before, after: size(path) + size(path + "-wal"), backup: backup)
    }
}
