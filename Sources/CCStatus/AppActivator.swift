import AppKit

/// 从菜单 / 通知传递过来的激活目标。
struct SessionTarget {
    let bundleId: String
    let cwd: String
}

/// 激活指定 bundle ID 的 app 到前台。
///
/// 行为契约:
/// - 编辑器类 app（VS Code / Cursor / Zed）：优先用 cwd 定位项目窗口
/// - 终端类 app：直接切到前台
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
    static func activate(bundleId: String, cwd: String? = nil) -> Bool {
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

        // Fallback / 终端类 app：现有 activate 逻辑
        // 先尝试 NSRunningApplication API
        if #available(macOS 14.0, *) {
            app.activate()
        } else {
            app.activate(options: .activateIgnoringOtherApps)
        }

        // AppleScript 走不同的系统路径，能更可靠地聚焦窗口
        let pid = app.processIdentifier
        let script = "tell application id \"\(bundleId)\" to activate"
        let appleScript = NSAppleScript(source: script)
        var error: NSDictionary?
        appleScript?.executeAndReturnError(&error)

        if error != nil {
            // AppleScript 失败时回退到 System Events
            let fallback = """
            tell application "System Events"
                set frontmost of process id \(pid) to true
            end tell
            """
            let fallbackScript = NSAppleScript(source: fallback)
            fallbackScript?.executeAndReturnError(nil)
        }

        return true
    }
}
