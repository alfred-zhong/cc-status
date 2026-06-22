import Foundation

/// Reads Claude Code session snapshots from `~/.claude/sessions/*.json`.
///
/// Each file is a single-line JSON snapshot of one session, structurally
/// identical to a single element of `claude agents --json` output. Naming
/// convention observed: `<pid>.json` (e.g. `44508.json`).
///
/// This replaces the previous subprocess-based `ClaudeMonitor` which forked
/// `claude agents --json` every refresh. File-based reading drops the
/// ~100ms Node.js fork cost and removes the `which claude` path detection.
class FileSessionReader {
    private let sessionsDir = NSHomeDirectory() + "/.claude/sessions"

    /// `true` when the sessions directory exists, meaning Claude Code
    /// has been run on this machine at least once.
    var isAvailable: Bool {
        FileManager.default.fileExists(atPath: sessionsDir)
    }

    /// Read all session snapshots in the directory.
    ///
    /// Returns `.success([])` (not an error) when the directory is missing,
    /// so the UI can render the "empty" state instead of an error state.
    /// Individual file parse failures are logged and skipped, not propagated,
    /// so one malformed file does not break the rest of the list.
    func fetchSessions() -> Result<[ClaudeSession], MonitorError> {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sessionsDir) else {
            return .success([])
        }

        let dirURL = URL(fileURLWithPath: sessionsDir)
        let files: [URL]
        do {
            files = try fm.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }
        } catch {
            return .failure(.directoryAccessError(error.localizedDescription))
        }

        let decoder = JSONDecoder()
        var sessions: [ClaudeSession] = []
        for file in files {
            do {
                let data = try Data(contentsOf: file)
                let session = try decoder.decode(ClaudeSession.self, from: data)
                // 与原 ClaudeMonitor 行为一致: 过滤掉没有 status 字段的会话
                if session.status != nil || session.state != nil {
                    sessions.append(session)
                }
            } catch {
                // 单文件解析失败不影响其他文件,仅记录日志
                NSLog("CCStatus: failed to parse \(file.lastPathComponent): \(error)")
            }
        }
        return .success(sessions)
    }
}

enum MonitorError: LocalizedError {
    case processError(String)
    case directoryAccessError(String)

    var errorDescription: String? {
        switch self {
        case .processError(let msg):
            return String(format: NSLocalizedString("文件读取错误: %@", comment: ""), msg)
        case .directoryAccessError(let msg):
            return String(format: NSLocalizedString("目录访问错误: %@", comment: ""), msg)
        }
    }
}
