import Foundation

class ClaudeMonitor {
    private var claudePath: String?
    private var isPolling = false

    init() {
        detectClaudePath()
    }

    /// Probe for claude CLI in common locations
    private func detectClaudePath() {
        let candidates = [
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
        ]

        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                claudePath = path
                return
            }
        }

        // Fallback: try login shell
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", "which claude"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !path.isEmpty
                {
                    claudePath = path
                }
            }
        } catch {
            // ignore
        }
    }

    /// Fetch sessions from `claude agents --json`
    func fetchSessions() -> Result<[ClaudeSession], MonitorError> {
        guard !isPolling else { return .failure(.alreadyPolling) }
        guard let claudePath else { return .failure(.claudeNotFound) }

        isPolling = true
        defer { isPolling = false }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = ["agents", "--json"]

        // Ensure the process inherits the right PATH
        var env = ProcessInfo.processInfo.environment
        let pathDirs = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        let currentPath = env["PATH"] ?? ""
        for dir in pathDirs {
            if !currentPath.contains(dir) {
                env["PATH"] = "\(currentPath):\(dir)"
                break
            }
        }
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return .failure(.processError(error.localizedDescription))
        }

        guard process.terminationStatus == 0 else {
            return .failure(.commandFailed(Int(process.terminationStatus)))
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()

        guard !data.isEmpty else {
            return .success([])
        }

        do {
            let sessions = try JSONDecoder().decode([ClaudeSession].self, from: data)
            // 过滤掉没有 status 字段的会话（进程已退出）
            let activeSessions = sessions.filter { $0.status != nil }
            return .success(activeSessions)
        } catch {
            return .failure(.jsonDecodeError(error.localizedDescription))
        }
    }

    var isAvailable: Bool { claudePath != nil }
}

enum MonitorError: LocalizedError {
    case claudeNotFound
    case alreadyPolling
    case processError(String)
    case commandFailed(Int)
    case jsonDecodeError(String)

    var errorDescription: String? {
        switch self {
        case .claudeNotFound:
            return "未检测到 Claude Code CLI"
        case .alreadyPolling:
            return "正在查询中"
        case .processError(let msg):
            return "进程错误: \(msg)"
        case .commandFailed(let code):
            return "命令执行失败 (退出码: \(code))"
        case .jsonDecodeError(let msg):
            return "JSON 解析错误: \(msg)"
        }
    }
}
