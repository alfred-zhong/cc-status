import AppKit

/// 激活指定 bundle ID 的 app 到前台。
///
/// 行为契约:
/// - 目标 app 已在跑 → 切到前台(不开新窗口)
/// - 目标 app 未在跑 → 返回 false(不自动启动,避免惊喜行为)
enum AppActivator {
    @discardableResult
    static func activate(bundleId: String) -> Bool {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
        guard let app = apps.first else {
            return false
        }
        return app.activate(options: .activateIgnoringOtherApps)
    }
}