import AppKit

/// 配置面板窗口控制器。
/// 通过菜单栏"配置"项打开,配置项分三组:
/// - 排序: autoSortSessions
/// - 菜单栏: showWaitingNameInMenuBar / showRunningNameInMenuBar / maxNameLengthInMenuBar
/// - 通知: desktopNotificationsEnabled
/// 设计原则: 极简自用,后续新增配置项只需往 NSView 里加控件,无需重构。
final class PreferencesWindowController: NSWindowController {
    private static let autoSortKey = "autoSortSessions"
    private static let showWaitingNameKey = "showWaitingNameInMenuBar"
    private static let showRunningNameKey = "showRunningNameInMenuBar"
    private static let maxNameLengthKey = "maxNameLengthInMenuBar"
    private static let notificationKey = "desktopNotificationsEnabled"
    // SPM `swift run` 模式下读不到 Info.plist,回落此值
    // 改版本时同步改 Info.plist 的 CFBundleShortVersionString
    private static let fallbackVersion = "0.1.2"

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "CCStatus 偏好设置"
        window.center()
        window.setFrameAutosaveName("CCStatusPreferencesWindow")  // 记忆位置

        super.init(window: window)

        // 分组标题辅助函数
        func makeSectionLabel(_ text: String) -> NSTextField {
            let label = NSTextField(labelWithString: text)
            label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
            label.textColor = NSColor.secondaryLabelColor
            label.translatesAutoresizingMaskIntoConstraints = false
            window.contentView?.addSubview(label)
            return label
        }

        // — 排序 —
        let sortLabel = makeSectionLabel("排序")

        let autoSortCheckbox = NSButton(
            checkboxWithTitle: "自动排序 session (等待中 → 工作中 → 空闲)",
            target: self,
            action: #selector(autoSortChanged(_:))
        )
        autoSortCheckbox.state = UserDefaults.standard.bool(forKey: Self.autoSortKey) ? .on : .off
        autoSortCheckbox.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(autoSortCheckbox)

        // — 菜单栏 —
        let menuBarLabel = makeSectionLabel("菜单栏")

        let waitingNameCheckbox = NSButton(
            checkboxWithTitle: "菜单栏显示等待中 session 名称",
            target: self,
            action: #selector(waitingNameChanged(_:))
        )
        waitingNameCheckbox.state = UserDefaults.standard.bool(forKey: Self.showWaitingNameKey) ? .on : .off
        waitingNameCheckbox.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(waitingNameCheckbox)

        let runningNameCheckbox = NSButton(
            checkboxWithTitle: "菜单栏显示运行中 session 名称",
            target: self,
            action: #selector(runningNameChanged(_:))
        )
        runningNameCheckbox.state = UserDefaults.standard.bool(forKey: Self.showRunningNameKey) ? .on : .off
        runningNameCheckbox.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(runningNameCheckbox)

        // 菜单栏 session 名最大长度 (NSPopUpButton 预设: 不限制 / 10 / 15 / 20 / 30 / 50)
        let maxLengthLabel = NSTextField(labelWithString: "菜单栏 session 名最大长度:")
        maxLengthLabel.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        maxLengthLabel.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(maxLengthLabel)

        let maxLengthPopup = NSPopUpButton()
        maxLengthPopup.translatesAutoresizingMaskIntoConstraints = false
        let popupItems: [(String, Int)] = [
            ("不限制", 0),
            ("10", 10),
            ("15", 15),
            ("20", 20),
            ("30", 30),
            ("50", 50),
        ]
        for (title, value) in popupItems {
            maxLengthPopup.addItem(withTitle: title)
            let lastIndex = maxLengthPopup.numberOfItems - 1
            maxLengthPopup.item(at: lastIndex)?.tag = value
        }
        let savedMax = UserDefaults.standard.integer(forKey: Self.maxNameLengthKey)
        maxLengthPopup.selectItem(withTag: savedMax)
        maxLengthPopup.target = self
        maxLengthPopup.action = #selector(maxNameLengthChanged(_:))
        window.contentView?.addSubview(maxLengthPopup)

        let maxLengthHint = NSTextField(labelWithString: "(0 为不限制)")
        maxLengthHint.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        maxLengthHint.textColor = NSColor.secondaryLabelColor
        maxLengthHint.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(maxLengthHint)

        // — 通知 —
        let notificationLabel = makeSectionLabel("通知")

        // 桌面通知开关
        let notificationCheckbox = NSButton(
            checkboxWithTitle: "桌面通知（session 等待输入时）",
            target: self,
            action: #selector(notificationToggleChanged(_:))
        )
        notificationCheckbox.state = UserDefaults.standard.bool(forKey: Self.notificationKey) ? .on : .off
        notificationCheckbox.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(notificationCheckbox)

        // 版本号:读 Info.plist 的 CFBundleShortVersionString,SPM 模式回落 fallbackVersion
        let versionString = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? Self.fallbackVersion
        let versionLabel = NSTextField(labelWithString: "v\(versionString)")
        versionLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        versionLabel.textColor = NSColor.secondaryLabelColor
        versionLabel.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(versionLabel)

        NSLayoutConstraint.activate([
            // 排序
            sortLabel.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 20),
            sortLabel.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 16),

            autoSortCheckbox.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 20),
            autoSortCheckbox.topAnchor.constraint(equalTo: sortLabel.bottomAnchor, constant: 6),
            autoSortCheckbox.trailingAnchor.constraint(lessThanOrEqualTo: window.contentView!.trailingAnchor, constant: -20),

            // 菜单栏
            menuBarLabel.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 20),
            menuBarLabel.topAnchor.constraint(equalTo: autoSortCheckbox.bottomAnchor, constant: 16),

            waitingNameCheckbox.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 20),
            waitingNameCheckbox.topAnchor.constraint(equalTo: menuBarLabel.bottomAnchor, constant: 6),
            waitingNameCheckbox.trailingAnchor.constraint(lessThanOrEqualTo: window.contentView!.trailingAnchor, constant: -20),

            runningNameCheckbox.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 20),
            runningNameCheckbox.topAnchor.constraint(equalTo: waitingNameCheckbox.bottomAnchor, constant: 8),
            runningNameCheckbox.trailingAnchor.constraint(lessThanOrEqualTo: window.contentView!.trailingAnchor, constant: -20),

            maxLengthLabel.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 20),
            maxLengthLabel.centerYAnchor.constraint(equalTo: maxLengthPopup.centerYAnchor),
            maxLengthLabel.trailingAnchor.constraint(lessThanOrEqualTo: maxLengthPopup.leadingAnchor, constant: -8),

            maxLengthPopup.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 220),
            maxLengthPopup.topAnchor.constraint(equalTo: runningNameCheckbox.bottomAnchor, constant: 8),

            maxLengthHint.leadingAnchor.constraint(equalTo: maxLengthPopup.trailingAnchor, constant: 8),
            maxLengthHint.centerYAnchor.constraint(equalTo: maxLengthPopup.centerYAnchor),
            maxLengthHint.trailingAnchor.constraint(lessThanOrEqualTo: window.contentView!.trailingAnchor, constant: -20),

            // 通知
            notificationLabel.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 20),
            notificationLabel.topAnchor.constraint(equalTo: maxLengthPopup.bottomAnchor, constant: 16),

            notificationCheckbox.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 20),
            notificationCheckbox.topAnchor.constraint(equalTo: notificationLabel.bottomAnchor, constant: 6),
            notificationCheckbox.trailingAnchor.constraint(lessThanOrEqualTo: window.contentView!.trailingAnchor, constant: -20),

            // 版本号
            versionLabel.centerXAnchor.constraint(equalTo: window.contentView!.centerXAnchor),
            versionLabel.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor, constant: -16),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    @objc private func autoSortChanged(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: Self.autoSortKey)
        NotificationCenter.default.post(name: .preferencesChanged, object: nil)
    }

    @objc private func waitingNameChanged(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: Self.showWaitingNameKey)
        NotificationCenter.default.post(name: .preferencesChanged, object: nil)
    }

    @objc private func runningNameChanged(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: Self.showRunningNameKey)
        NotificationCenter.default.post(name: .preferencesChanged, object: nil)
    }

    @objc private func maxNameLengthChanged(_ sender: NSPopUpButton) {
        UserDefaults.standard.set(sender.selectedTag(), forKey: Self.maxNameLengthKey)
        NotificationCenter.default.post(name: .preferencesChanged, object: nil)
    }

    @objc private func notificationToggleChanged(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: Self.notificationKey)
        NotificationCenter.default.post(name: .preferencesChanged, object: nil)
    }
}

extension Notification.Name {
    static let preferencesChanged = Notification.Name("CCStatus.preferencesChanged")
}
