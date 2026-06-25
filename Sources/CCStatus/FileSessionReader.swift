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
    private let projectsDir = NSHomeDirectory() + "/.claude/projects"

    /// claude-vscode 会话推断为"工作中"的 mtime 阈值（秒）。
    /// jsonl 在 Claude 工作期间会持续追加；用户思考/空闲时不写。
    /// 阈值过小会闪烁，过大会把空闲也判为工作。15s 经验值。
    private let vscodeBusyThresholdSeconds: TimeInterval = 15

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
                var session = try decoder.decode(ClaudeSession.self, from: data)
                // 与原 ClaudeMonitor 行为一致: 过滤掉没有 status 字段的会话
                // 例外: claude-vscode entrypoint 不写 status/state，但确实是活跃 session，需要放行
                if session.status != nil || session.state != nil || session.isVSCodeEntrypoint {
                    if session.isVSCodeEntrypoint {
                        session.vscodeInferredBusy = inferVSCodeBusy(for: session)
                    }
                    sessions.append(session)
                }
            } catch {
                // 单文件解析失败不影响其他文件,仅记录日志
                NSLog("CCStatus: failed to parse \(file.lastPathComponent): \(error)")
            }
        }
        return .success(sessions)
    }

    /// 通过 `~/.claude/projects/<encoded-cwd>/<sessionId>.jsonl` 的 mtime 判断
    /// claude-vscode 会话当前是否在工作。距今 < 阈值 → busy。
    /// 找不到 jsonl 时返回 false（视为空闲，比错判为 busy 安全）。
    private func inferVSCodeBusy(for session: ClaudeSession) -> Bool {
        guard let sessionId = session.sessionId,
              let jsonlPath = locateJsonl(cwd: session.cwd, sessionId: sessionId),
              let attrs = try? FileManager.default.attributesOfItem(atPath: jsonlPath),
              let mtime = attrs[.modificationDate] as? Date else {
            return false
        }
        return Date().timeIntervalSince(mtime) < vscodeBusyThresholdSeconds
    }

    /// Claude Code 把 cwd 编码为 projects 子目录名时，将所有非字母数字字符替换为 `-`
    /// （已观测到 `/`、`.`、`_` 都会被替换）。先按这个规则尝试；失败再 fallback 扫描 projects/*/<sessionId>.jsonl。
    private func locateJsonl(cwd: String, sessionId: String) -> String? {
        let encoded = String(cwd.unicodeScalars.map { scalar -> Character in
            let c = Character(scalar)
            return c.isLetter || c.isNumber ? c : "-"
        })
        let primary = "\(projectsDir)/\(encoded)/\(sessionId).jsonl"
        if FileManager.default.fileExists(atPath: primary) { return primary }
        // Fallback：扫一遍 projects/*/<sessionId>.jsonl
        let fm = FileManager.default
        guard let subdirs = try? fm.contentsOfDirectory(atPath: projectsDir) else { return nil }
        for sub in subdirs {
            let candidate = "\(projectsDir)/\(sub)/\(sessionId).jsonl"
            if fm.fileExists(atPath: candidate) { return candidate }
        }
        return nil
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
