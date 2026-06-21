import AppKit

/// 配置面板窗口控制器。
/// 通过菜单栏"配置"项打开,目前只承载一个开关:自动排序 session。
/// 设计原则: 极简自用,后续新增配置项只需往 NSView 里加控件,无需重构。
final class PreferencesWindowController: NSWindowController {
    private static let autoSortKey = "autoSortSessions"

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 140),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "CCStatus 偏好设置"
        window.center()
        window.setFrameAutosaveName("CCStatusPreferencesWindow")  // 记忆位置

        super.init(window: window)

        let checkbox = NSButton(
            checkboxWithTitle: "自动排序 session (等待中 → 工作中 → 空闲)",
            target: self,
            action: #selector(autoSortChanged(_:))
        )
        checkbox.state = UserDefaults.standard.bool(forKey: Self.autoSortKey) ? .on : .off
        checkbox.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(checkbox)
        NSLayoutConstraint.activate([
            checkbox.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 20),
            checkbox.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 24),
            checkbox.trailingAnchor.constraint(lessThanOrEqualTo: window.contentView!.trailingAnchor, constant: -20),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    @objc private func autoSortChanged(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: Self.autoSortKey)
        NotificationCenter.default.post(name: .preferencesChanged, object: nil)
    }
}

extension Notification.Name {
    static let preferencesChanged = Notification.Name("CCStatus.preferencesChanged")
}