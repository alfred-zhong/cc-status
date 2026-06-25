import AppKit

/// 从菜单 / 通知传递过来的激活目标。
struct SessionTarget {
    let bundleId: String
    let cwd: String
    /// session 进程 PID，用于精确定位 iTerm 等多窗口/多 tab 终端的具体 session。
    /// nil 时退回到"只激活 app"的旧行为。
    var pid: Int?
}

/// 激活指定 bundle ID 的 app 到前台。
///
/// 行为契约:
/// - 编辑器类 app（VS Code / Cursor / Zed）：优先用 cwd 定位项目窗口
/// - iTerm：传入 PID 时通过 tty 精确选中对应 session/tab/window
/// - 其他终端类 app：直接切到前台
/// - 目标 app 已在跑 → 切到前台并聚焦窗口
/// - 目标 app 未在跑 → 返回 false（不自动启动，避免惊喜行为）
enum AppActivator {
    /// 会用 `NSWorkspace.open(cwdURL, withApplicationAt:)` 聚焦项目窗口的编辑器 bundle ID。
    /// 需要与 `HostApp.defaultWhitelist` 中新增编辑器保持同步。
    private static let editorBundleIds: Set<String> = [
        "com.microsoft.VSCode",
        "com.todesktop.230313mzl4w4u92",  // Cursor
        "dev.zed.Zed",
    ]

    @discardableResult
    static func activate(bundleId: String, cwd: String? = nil, pid: Int? = nil) -> Bool {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
        guard let app = apps.first else {
            return false
        }

        // 编辑器 app + 有 cwd → 尝试用项目目录定位窗口
        if let cwd, !cwd.isEmpty, editorBundleIds.contains(bundleId) {
            let cwdURL = URL(fileURLWithPath: cwd)
            if FileManager.default.fileExists(atPath: cwd),
               let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
            {
                let semaphore = DispatchSemaphore(value: 0)
                var opened = false
                Task {
                    do {
                        try await NSWorkspace.shared.open(
                            [cwdURL],
                            withApplicationAt: appURL,
                            configuration: NSWorkspace.OpenConfiguration()
                        )
                        opened = true
                    } catch {
                        // NSWorkspace.open 失败 → 走 fallback
                    }
                    semaphore.signal()
                }
                semaphore.wait()
                if opened { return true }
            }
        }

        // iTerm + 有 PID → 通过 tty 精确选中对应 session
        if bundleId == "com.googlecode.iterm2", let pid, let tty = ttyForPid(pid) {
            if focusITermSession(tty: tty) {
                // iTerm AppleScript 内部已经 activate，直接返回
                return true
            }
            // 没匹配到 → 继续走通用 activate
        }

        // Fallback / 终端类 app：现有 activate 逻辑
        // 先尝试 NSRunningApplication API
        if #available(macOS 14.0, *) {
            app.activate()
        } else {
            app.activate(options: .activateIgnoringOtherApps)
        }

        // AppleScript 走不同的系统路径，能更可靠地聚焦窗口
        let appPid = app.processIdentifier
        let script = "tell application id \"\(bundleId)\" to activate"
        let appleScript = NSAppleScript(source: script)
        var error: NSDictionary?
        appleScript?.executeAndReturnError(&error)

        if error != nil {
            // AppleScript 失败时回退到 System Events
            let fallback = """
            tell application "System Events"
                set frontmost of process id \(appPid) to true
            end tell
            """
            let fallbackScript = NSAppleScript(source: fallback)
            fallbackScript?.executeAndReturnError(nil)
        }

        return true
    }

    /// 通过 `ps` 取指定 PID 的 tty。返回形如 `/dev/ttys000`；进程不存在或非 tty 进程时返回 nil。
    private static func ttyForPid(_ pid: Int) -> String? {
        let task = Process()
        task.launchPath = "/bin/ps"
        task.arguments = ["-p", "\(pid)", "-o", "tty="]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
        } catch {
            return nil
        }
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // 进程不存在 → 空串；tty 列为 `??` → 后台进程，无终端
        guard !raw.isEmpty, raw != "??" else { return nil }
        return raw.hasPrefix("/dev/") ? raw : "/dev/\(raw)"
    }

    /// 通过 AppleScript 在 iTerm 里找到 tty 等于目标值的 session，选中其窗口/tab/session 并激活。
    /// 找到并选中返回 true；未找到返回 false（让调用方走通用 activate）。
    private static func focusITermSession(tty: String) -> Bool {
        let script = """
        tell application "iTerm"
          repeat with w in windows
            repeat with t in tabs of w
              repeat with s in sessions of t
                if tty of s is "\(tty)" then
                  tell s to select
                  tell t to select
                  tell w to select
                  activate
                  return "ok"
                end if
              end repeat
            end repeat
          end repeat
          return "miss"
        end tell
        """
        let apple = NSAppleScript(source: script)
        var error: NSDictionary?
        let result = apple?.executeAndReturnError(&error)
        if error != nil { return false }
        return result?.stringValue == "ok"
    }
}
