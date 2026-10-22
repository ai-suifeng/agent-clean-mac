import Foundation

/// Expands rule path patterns: `~`, `{a,b}`, `*`/`?` per path component and `**` for any depth.
/// Matching never follows symlinks and only returns paths that exist.
public enum Glob {
    public static func expand(_ pattern: String, home: String) -> [String] {
        var results: [String] = []
        for p in expandBraces(pattern) {
            let abs = p.hasPrefix("~/") ? home + p.dropFirst(1) : (p == "~" ? home : p)
            results += walk(abs)
        }
        var seen = Set<String>()
        return results.filter { seen.insert($0).inserted }
    }

    static func expandBraces(_ s: String) -> [String] {
        guard let open = s.firstIndex(of: "{"), let close = s[open...].firstIndex(of: "}") else { return [s] }
        let head = s[..<open], tail = s[s.index(after: close)...]
        return s[s.index(after: open)..<close].split(separator: ",", omittingEmptySubsequences: false)
            .flatMap { expandBraces(String(head + $0 + tail)) }
    }

    static func hasWildcard(_ c: Substring) -> Bool { c.contains("*") || c.contains("?") || c.contains("[") }

    static func walk(_ path: String) -> [String] {
        let comps = path.split(separator: "/", omittingEmptySubsequences: true)
        var current = ["/"]
        for (i, comp) in comps.enumerated() {
            var next: [String] = []
            if comp == "**" {
                for dir in current { next.append(dir); next += descendantDirs(dir) }
            } else if hasWildcard(comp) {
                for dir in current {
                    for name in list(dir) where fnmatch(String(comp), name, 0) == 0 {
                        next.append(join(dir, name))
                    }
                }
            } else {
                next = current.map { join($0, String(comp)) }
                // Intermediate literal components must be directories (symlinked parents like /var are fine).
                if i < comps.count - 1 { next = next.filter(isDirFollowingLinks) }
            }
            current = next
            if current.isEmpty { return [] }
        }
        return current.filter(exists)
    }

    static func join(_ dir: String, _ name: String) -> String { dir == "/" ? "/" + name : dir + "/" + name }

    static func list(_ dir: String) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).filter { $0 != ".DS_Store" }
    }

    static func descendantDirs(_ dir: String) -> [String] {
        var out: [String] = []
        for name in list(dir) {
            let p = join(dir, name)
            if isDir(p) { out.append(p); out += descendantDirs(p) }
        }
        return out
    }

    static func lstatMode(_ p: String) -> mode_t? {
        var st = stat()
        return lstat(p, &st) == 0 ? st.st_mode : nil
    }

    static func exists(_ p: String) -> Bool { lstatMode(p) != nil }
    static func isDir(_ p: String) -> Bool { lstatMode(p).map { $0 & S_IFMT == S_IFDIR } ?? false }

    static func isDirFollowingLinks(_ p: String) -> Bool {
        var st = stat()
        return stat(p, &st) == 0 && st.st_mode & S_IFMT == S_IFDIR
    }
}

extension String {
    /// True when `self` equals `other` or lies inside it.
    func isWithin(_ other: String) -> Bool { self == other || hasPrefix(other.hasSuffix("/") ? other : other + "/") }
}
