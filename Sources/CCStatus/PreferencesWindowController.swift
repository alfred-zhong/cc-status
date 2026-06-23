import AppKit

/// 配置面板窗口控制器。
/// 通过菜单栏"配置"项打开,配置项分三组:
/// - 通知: desktopNotificationsEnabled
/// - 菜单栏: showWaitingNameInMenuBar / showRunningNameInMenuBar / showIdleNameInMenuBar / maxNameLengthInMenuBar
/// - 列表: autoSortSessions
/// 设计原则: 极简自用,后续新增配置项只需往 NSView 里加控件,无需重构。
final class PreferencesWindowController: NSWindowController {
    private static let autoSortKey = "autoSortSessions"
    private static let showWaitingNameKey = "showWaitingNameInMenuBar"
    private static let showRunningNameKey = "showRunningNameInMenuBar"
    private static let showIdleNameKey = "showIdleNameInMenuBar"
    private static let maxNameLengthKey = "maxNameLengthInMenuBar"
    private static let notificationKey = "desktopNotificationsEnabled"
    // SPM `swift run` 模式下读不到 Info.plist,回落此值
    // 改版本时同步改 Info.plist 的 CFBundleShortVersionString
    private static let fallbackVersion = "0.2.1"

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = NSLocalizedString("CCStatus 偏好设置", comment: "")
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

        // — 通知 —
        let notificationLabel = makeSectionLabel(NSLocalizedString("通知", comment: ""))

        let notificationCheckbox = NSButton(
            checkboxWithTitle: NSLocalizedString("桌面通知（session 等待输入且应用处于后台时）", comment: ""),
            target: self,
            action: #selector(notificationToggleChanged(_:))
        )
        notificationCheckbox.state = UserDefaults.standard.bool(forKey: Self.notificationKey) ? .on : .off
        notificationCheckbox.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(notificationCheckbox)

        // — 菜单栏 —
        let menuBarLabel = makeSectionLabel(NSLocalizedString("菜单栏", comment: ""))

        // 辅助函数：创建带图标的开关单元
        func makeStateToggle(
            tag: Int, stateText: String, dotColor: NSColor, key: String
        ) -> NSStackView {
            let checkbox = NSButton()
            checkbox.setButtonType(.switch)
            checkbox.state = UserDefaults.standard.bool(forKey: key) ? .on : .off
            checkbox.target = self
            checkbox.action = #selector(menuBarNameToggleChanged(_:))
            checkbox.tag = tag
            checkbox.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                checkbox.widthAnchor.constraint(equalToConstant: 20),
                checkbox.heightAnchor.constraint(equalToConstant: 20),
            ])

            let dotImage = NSImage(
                systemSymbolName: "circle.fill",
                accessibilityDescription: stateText
            )
            dotImage?.isTemplate = true
            let dotView = NSImageView(image: dotImage!)
            dotView.contentTintColor = dotColor
            dotView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                dotView.widthAnchor.constraint(equalToConstant: 12),
                dotView.heightAnchor.constraint(equalToConstant: 12),
            ])

            let label = NSTextField(labelWithString: stateText)
            label.font = NSFont.systemFont(ofSize: 13, weight: .regular)
            label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
            label.translatesAutoresizingMaskIntoConstraints = false

            let unit = NSStackView(views: [checkbox, dotView, label])
            unit.orientation = .horizontal
            unit.alignment = .centerY
            unit.spacing = 4
            unit.translatesAutoresizingMaskIntoConstraints = false
            return unit
        }

        let waitingUnit = makeStateToggle(
            tag: 0,
            stateText: NSLocalizedString("等待中", comment: ""),
            dotColor: .systemOrange,
            key: Self.showWaitingNameKey
        )
        let runningUnit = makeStateToggle(
            tag: 1,
            stateText: NSLocalizedString("运行中", comment: ""),
            dotColor: .systemGreen,
            key: Self.showRunningNameKey
        )
        let idleUnit = makeStateToggle(
            tag: 2,
            stateText: NSLocalizedString("空闲", comment: ""),
            dotColor: .systemGray,
            key: Self.showIdleNameKey
        )

        let nameToggleLabel = NSTextField(labelWithString: NSLocalizedString("显示 session 名称:", comment: ""))
        nameToggleLabel.font = NSFont.systemFont(ofSize: 13, weight: .regular)

        let nameTogglesRow = NSStackView(views: [waitingUnit, runningUnit, idleUnit])
        nameTogglesRow.orientation = .horizontal
        nameTogglesRow.distribution = .equalSpacing
        nameTogglesRow.spacing = 8

        let nameToggleGroup = NSStackView(views: [nameToggleLabel, nameTogglesRow])
        nameToggleGroup.orientation = .horizontal
        nameToggleGroup.alignment = .centerY
        nameToggleGroup.spacing = 12
        nameToggleGroup.distribution = .fill
        nameToggleGroup.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(nameToggleGroup)

        let maxLengthLabel = NSTextField(labelWithString: NSLocalizedString("session 名最大长度:", comment: ""))
        maxLengthLabel.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        maxLengthLabel.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(maxLengthLabel)

        let maxLengthPopup = NSPopUpButton()
        maxLengthPopup.translatesAutoresizingMaskIntoConstraints = false
        let popupItems: [(String, Int)] = [
            (NSLocalizedString("不限制", comment: ""), 0),
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


        // — 列表 —
        let listLabel = makeSectionLabel(NSLocalizedString("列表", comment: ""))

        let autoSortCheckbox = NSButton(
            checkboxWithTitle: NSLocalizedString("自动排序 (等待中 → 工作中 → 空闲)", comment: ""),
            target: self,
            action: #selector(autoSortChanged(_:))
        )
        autoSortCheckbox.state = UserDefaults.standard.bool(forKey: Self.autoSortKey) ? .on : .off
        autoSortCheckbox.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(autoSortCheckbox)

        // 版本号
        let versionString = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? Self.fallbackVersion
        let versionLabel = NSTextField(labelWithString: "v\(versionString)")
        versionLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        versionLabel.textColor = NSColor.secondaryLabelColor
        versionLabel.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(versionLabel)

        NSLayoutConstraint.activate([
            // 通知
            notificationLabel.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 20),
            notificationLabel.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 16),

            notificationCheckbox.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 20),
            notificationCheckbox.topAnchor.constraint(equalTo: notificationLabel.bottomAnchor, constant: 6),
            notificationCheckbox.trailingAnchor.constraint(lessThanOrEqualTo: window.contentView!.trailingAnchor, constant: -20),

            // 菜单栏
            menuBarLabel.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 20),
            menuBarLabel.topAnchor.constraint(equalTo: notificationCheckbox.bottomAnchor, constant: 16),

            nameToggleGroup.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 20),
            nameToggleGroup.topAnchor.constraint(equalTo: menuBarLabel.bottomAnchor, constant: 6),
            nameToggleGroup.trailingAnchor.constraint(lessThanOrEqualTo: window.contentView!.trailingAnchor, constant: -20),

            maxLengthLabel.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 20),
            maxLengthLabel.centerYAnchor.constraint(equalTo: maxLengthPopup.centerYAnchor),
            maxLengthLabel.trailingAnchor.constraint(lessThanOrEqualTo: maxLengthPopup.leadingAnchor, constant: -8),

            maxLengthPopup.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 180),
            maxLengthPopup.topAnchor.constraint(equalTo: nameToggleGroup.bottomAnchor, constant: 8),


            // 列表
            listLabel.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 20),
            listLabel.topAnchor.constraint(equalTo: maxLengthPopup.bottomAnchor, constant: 16),

            autoSortCheckbox.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 20),
            autoSortCheckbox.topAnchor.constraint(equalTo: listLabel.bottomAnchor, constant: 6),
            autoSortCheckbox.trailingAnchor.constraint(lessThanOrEqualTo: window.contentView!.trailingAnchor, constant: -20),

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

    @objc private func menuBarNameToggleChanged(_ sender: NSButton) {
        let key: String
        switch sender.tag {
        case 1:  key = Self.showRunningNameKey
        case 2:  key = Self.showIdleNameKey
        default: key = Self.showWaitingNameKey  // tag=0
        }
        UserDefaults.standard.set(sender.state == .on, forKey: key)
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
