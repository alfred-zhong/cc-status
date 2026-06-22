import AppKit

/// 激活指定 bundle ID 的 app 到前台。
///
/// 行为契约:
/// - 目标 app 已在跑 → 切到前台并聚焦窗口
/// - 目标 app 未在跑 → 返回 false(不自动启动,避免惊喜行为)
enum AppActivator {
    @discardableResult
    static func activate(bundleId: String) -> Bool {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
        guard let app = apps.first else {
            return false
        }

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
