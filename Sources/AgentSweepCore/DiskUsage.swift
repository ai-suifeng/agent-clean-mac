import Foundation

public struct Usage: Sendable, Hashable {
    public var bytes: Int64 = 0
    public var files: Int = 0
    public var newest: Date?
}

/// Fast physical walk with fts. Sizes are allocated blocks, hard links are counted once.
public enum DiskUsage {
    public static func walkFiles(_ root: String, _ body: (String, stat) -> Void) {
        var st = stat()
        guard lstat(root, &st) == 0 else { return }
        if st.st_mode & S_IFMT != S_IFDIR { body(root, st); return }
        let cRoot = strdup(root)
        defer { free(cRoot) }
        var argv: [UnsafeMutablePointer<CChar>?] = [cRoot, nil]
        guard let fts = fts_open(&argv, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else { return }
        defer { fts_close(fts) }
        while let ent = fts_read(fts) {
            switch Int32(ent.pointee.fts_info) {
            case FTS_F, FTS_SL, FTS_SLNONE, FTS_DEFAULT:
                if let sp = ent.pointee.fts_statp { body(String(cString: ent.pointee.fts_path), sp.pointee) }
            default: break
            }
        }
    }

    public static func measure(_ path: String) -> Usage {
        var u = Usage()
        var seen = Set<[UInt64]>()
        walkFiles(path) { _, st in
            if st.st_nlink > 1, !seen.insert([UInt64(st.st_dev), st.st_ino]).inserted { return }
            u.bytes += Int64(st.st_blocks) * 512
            u.files += 1
            let m = st.mtime
            if u.newest.map({ m > $0 }) ?? true { u.newest = m }
        }
        if u.newest == nil {
            var st = stat()
            if lstat(path, &st) == 0 { u.newest = st.mtime }
        }
        return u
    }
}

extension stat {
    var mtime: Date { Date(timeIntervalSince1970: TimeInterval(st_mtimespec.tv_sec)) }
}

public enum ByteFormat {
    public static func string(_ bytes: Int64) -> String {
        if bytes <= 0 { return "0 KB" }
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        return f.string(fromByteCount: bytes)
    }

    /// Number and unit apart, for the big readout.
    public static func parts(_ bytes: Int64) -> (String, String) {
        let gb = Double(bytes) / 1e9
        if gb >= 100 { return (String(format: "%.0f", gb), "GB") }
        if gb >= 1 { return (String(format: "%.1f", gb), "GB") }
        if bytes >= 1_000_000 { return (String(format: "%.0f", Double(bytes) / 1e6), "MB") }
        return (String(format: "%.0f", Double(max(0, bytes)) / 1e3), "KB")
    }
}
