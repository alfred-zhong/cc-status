import Foundation

/// 白名单里的一项:已知的、能跑 Claude Code 的终端/IDE。
struct HostApp: Equatable {
    let bundleId: String
    /// 显示在菜单里的简称,例如 "Kitty" / "VSCode"。
    let shortName: String
    /// 进程名数组(`proc_pidinfo` 拿到的 `pbi_comm`)。需要支持同一 app 的多个进程名
    /// (例如 VSCode 的主进程 "Code" 和辅助进程 "Code Helper")。
    let processNames: [String]

    func matches(processName: String) -> Bool {
        processNames.contains(processName)
    }
}

extension HostApp {
    /// 默认白名单:覆盖主流终端和 IDE。
    /// 新增 app 在这里加一行即可。
    static let defaultWhitelist: [HostApp] = [
        HostApp(bundleId: "net.kovidgoyal.kitty",         shortName: "Kitty",     processNames: ["kitty"]),
        HostApp(bundleId: "com.googlecode.iterm2",        shortName: "iTerm",     processNames: ["iTerm2"]),
        HostApp(bundleId: "com.apple.Terminal",           shortName: "Terminal",  processNames: ["Terminal"]),
        HostApp(bundleId: "com.microsoft.VSCode",         shortName: "VSCode",    processNames: ["Code", "Code Helper"]),
        HostApp(bundleId: "com.todesktop.230313mzl4w4u92", shortName: "Cursor",    processNames: ["Cursor"]),
        HostApp(bundleId: "dev.zed.Zed",                  shortName: "Zed",       processNames: ["zed"]),
        HostApp(bundleId: "com.mitchellh.ghostty",        shortName: "Ghostty",   processNames: ["ghostty"]),
        HostApp(bundleId: "dev.warp.Warp-Stable",         shortName: "Warp",      processNames: ["warp"]),
        HostApp(bundleId: "org.alacritty",                shortName: "Alacritty", processNames: ["alacritty"]),
    ]
}