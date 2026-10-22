import Foundation

public enum ProcessDetector {
    /// Executable paths of every process the current user can see.
    public static func executablePaths() -> [String] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) * 2)
        let n = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        var buf = [CChar](repeating: 0, count: 4096)
        return pids.prefix(Int(max(0, n))).compactMap { pid in
            guard pid > 0, proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 else { return nil }
            return String(cString: buf)
        }
    }

    /// True when a process of the tool is running: an app bundle `<Name>.app` or a binary named `<name>`.
    public static func isRunning(_ tool: ToolDef, paths: [String]? = nil) -> Bool {
        let names = tool.detect.processes ?? []
        guard !names.isEmpty else { return false }
        let paths = paths ?? executablePaths()
        return paths.contains { p in
            let base = (p as NSString).lastPathComponent.lowercased()
            return names.contains { n in
                base == n.lowercased() || p.contains("/\(n).app/Contents/")
            }
        }
    }
}
