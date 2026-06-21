import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let monitor = ClaudeMonitor()
    private let detector = HostAppDetector()
    private var timer: Timer?
    private var animationTimer: Timer?
    private var animationStart: Date = Date()
    private var sessions: [ClaudeSession] = []
    private var lastError: String?
    private var currentState: IconState = .idle

    // 文件监听（FSEventStream 方案）
    private var fileWatcher: FileWatcher?
    private var debounceWorkItem: DispatchWorkItem?
    private let debounceQueue = DispatchQueue(label: "ccstatus.debounce", qos: .utility)
    private let sessionsDir = NSHomeDirectory() + "/.claude/sessions"

    // 配置面板
    private lazy var preferencesWindow: PreferencesWindowController = PreferencesWindowController()
    private static let autoSortKey = "autoSortSessions"
    private static let showWaitingNameKey = "showWaitingNameInMenuBar"
    private static let showRunningNameKey = "showRunningNameInMenuBar"

    // session 状态追踪：用于 auto-sort 在同档内按"状态变化时间"二次排序
    private var lastSeenStatus: [String: String] = [:]
    private var lastStateChange: [String: Date] = [:]

    private enum IconState {
        case error
        case empty
        case blocked
        case working
        case idle
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 注册配置默认值：首次启动时所有 toggle 默认开启
        UserDefaults.standard.register(defaults: [
            Self.autoSortKey: true,
            Self.showWaitingNameKey: true,
            Self.showRunningNameKey: true,
        ])

        // 监听配置变更通知，触发菜单重新构建
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePreferencesChanged),
            name: .preferencesChanged,
            object: nil
        )

        setupStatusItem()
        poll()

        // 兜底轮询：每 5 秒（已临时关闭，测试纯文件监听）
        // timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
        //     self?.poll()
        // }

        // 文件监听：sessions 目录变化时立即刷新
        startWatchingSessions()

        // 监听系统睡眠/唤醒，重启监听器避免失效
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func handleSleep() {
        // 睡眠前停止监听器，避免唤醒后状态混乱
        fileWatcher?.stop()
        fileWatcher = nil
    }

    @objc private func handleWake() {
        // 唤醒后重启监听器 + 主动同步一次
        startWatchingSessions()
        poll()
    }

    @objc private func handleBecomeActive() {
        // 应用重新激活时同步一次（防止长时间后台后状态过期）
        poll()
    }

    // MARK: - File Watching

    private func startWatchingSessions() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sessionsDir) else {
            // 目录不存在，退到纯轮询
            return
        }

        let watcher = FileWatcher(path: sessionsDir) { [weak self] in
            self?.scheduleDebouncedPoll()
        }
        watcher.start()
        fileWatcher = watcher
    }

    private func scheduleDebouncedPoll() {
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            DispatchQueue.main.async {
                self?.poll()
            }
        }
        debounceWorkItem = work
        // 100ms 去抖，避免短时间内多次刷新
        debounceQueue.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    // MARK: - Status Item Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon()
    }

    // MARK: - Polling

    private func poll() {
        let result = monitor.fetchSessions()

        switch result {
        case .success(let sessions):
            trackStatusChanges(sessions)
            self.sessions = sessions
            self.lastError = nil
        case .failure(let error):
            self.lastError = error.localizedDescription
        }

        // 预热 detector 缓存(新 PID 走进程树,已有 PID 直接命中)
        // 并清掉已不存在的 PID 缓存条目。
        let livePids = Set(sessions.compactMap { $0.pid })
        for pid in livePids {
            _ = detector.detect(forPid: pid)
        }
        detector.pruneCache(keepingLivePids: livePids)

        DispatchQueue.main.async { [weak self] in
            self?.updateIcon()
            self?.updateMenu()
        }
    }

    // MARK: - Icon Update

    private func updateIcon() {
        guard let button = statusItem.button else { return }

        let image: NSImage
        let tintColor: NSColor
        let newState: IconState

        if !monitor.isAvailable || lastError != nil {
            // Claude not found or error - 灰色空心
            image = NSImage(systemSymbolName: "circle", accessibilityDescription: "CC Status")!
            tintColor = .systemGray
            newState = .error
        } else if sessions.isEmpty {
            // No sessions - 灰色空心
            image = NSImage(systemSymbolName: "circle", accessibilityDescription: "CC Status")!
            tintColor = .systemGray
            newState = .empty
        } else if sessions.contains(where: { $0.isBlocked }) {
            // Any session waiting for input - 橙色实心
            image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "CC Status")!
            tintColor = .systemOrange
            newState = .blocked
        } else if sessions.contains(where: { $0.isBusy }) {
            // Any session working - 绿色实心
            image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "CC Status")!
            tintColor = .systemGreen
            newState = .working
        } else {
            // All idle - 灰色实心
            image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "CC Status")!
            tintColor = .systemGray
            newState = .idle
        }

        let tintedImage = NSImage(size: image.size, flipped: false) { rect in
            tintColor.set()
            rect.fill()
            image.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1.0)
            return true
        }
        tintedImage.isTemplate = false
        button.image = tintedImage

        // 等待中 / 运行中的 session：把项目名追加到图标后面（受各自 toggle 控制）
        if newState == .blocked {
            if UserDefaults.standard.bool(forKey: Self.showWaitingNameKey) {
                let blockedNames = sortedForDisplay(sessions).filter { $0.isBlocked }
                button.title = blockedNames.first?.projectName ?? ""
            } else {
                button.title = ""
            }
        } else if newState == .working {
            if UserDefaults.standard.bool(forKey: Self.showRunningNameKey) {
                let workingNames = sortedForDisplay(sessions).filter { $0.isBusy }
                button.title = workingNames.first?.projectName ?? ""
            } else {
                button.title = ""
            }
        } else {
            button.title = ""
        }

        // 管理动画：仅在 working 状态下脉动
        if newState == .working {
            if animationTimer == nil {
                animationStart = Date()
                animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                    self?.tickAnimation()
                }
            }
        } else {
            animationTimer?.invalidate()
            animationTimer = nil
            button.alphaValue = 1.0
        }
        currentState = newState
    }

    private func tickAnimation() {
        guard let button = statusItem.button else { return }
        // 1.5 秒一个呼吸周期，alpha 在 0.4 ~ 1.0 之间
        let elapsed = Date().timeIntervalSince(animationStart)
        let phase = (elapsed.truncatingRemainder(dividingBy: 1.5)) / 1.5
        let alpha = 0.4 + 0.6 * (0.5 - 0.5 * cos(phase * 2 * .pi))
        button.alphaValue = CGFloat(alpha)
    }

    // MARK: - Menu Update

    private func updateMenu() {
        let menu = NSMenu()

        if let error = lastError {
            let item = NSMenuItem(title: error, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else if sessions.isEmpty {
            let item = NSMenuItem(title: "无活跃 session", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            for session in sortedForDisplay(sessions) {
                let statusColor: NSColor
                let statusDot: String
                if session.isBlocked {
                    statusColor = .systemOrange  // 等待输入
                    statusDot = "●"
                } else if session.isBusy {
                    statusColor = .systemGreen  // 运行中
                    statusDot = "●"
                } else {
                    statusColor = .systemGray  // 空闲
                    statusDot = "●"
                }

                // 查找宿主 app;找不到就显示"未知"且不可点击
                let hostApp = session.pid.flatMap { detector.detect(forPid: $0) }
                let hostSegment = hostApp.map { " (\($0.shortName))" } ?? " (未知)"

                let restText = " \(session.projectName)\(hostSegment) — \(session.statusDisplay) (\(session.durationDisplay))"
                let attributedTitle = NSMutableAttributedString()
                attributedTitle.append(NSAttributedString(
                    string: statusDot,
                    attributes: [.foregroundColor: statusColor, .font: NSFont.systemFont(ofSize: 13, weight: .bold)]
                ))
                attributedTitle.append(NSAttributedString(string: restText))

                let item = NSMenuItem()
                item.attributedTitle = attributedTitle
                if let hostApp {
                    item.target = self
                    item.action = #selector(activateSession(_:))
                    item.representedObject = hostApp.bundleId
                } else {
                    item.isEnabled = false
                }
                menu.addItem(item)
            }
        }

        menu.addItem(NSMenuItem.separator())

        let refreshItem = NSMenuItem(title: "刷新", action: #selector(refresh), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let preferencesItem = NSMenuItem(title: "配置", action: #selector(showPreferences), keyEquivalent: ",")
        preferencesItem.target = self
        menu.addItem(preferencesItem)

        let quitItem = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Actions

    @objc private func refresh() {
        poll()
    }

    @objc private func activateSession(_ sender: NSMenuItem) {
        guard let bundleId = sender.representedObject as? String else { return }
        AppActivator.activate(bundleId: bundleId)
    }

    @objc private func quit() {
        animationTimer?.invalidate()
        animationTimer = nil
        timer?.invalidate()
        timer = nil
        fileWatcher?.stop()
        fileWatcher = nil
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Preferences

    @objc private func showPreferences() {
        preferencesWindow.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func handlePreferencesChanged() {
        updateMenu()
    }

    // MARK: - Sorting

    /// 追踪每个 session 的 status 变化,记录最近一次变化时间。
    /// 用于 auto-sort 同档内按"状态变化时间"二次排序。
    private func trackStatusChanges(_ sessions: [ClaudeSession]) {
        let now = Date()
        let liveIds = Set(sessions.map { $0.displayId })
        for session in sessions {
            let status = session.statusDisplay
            if lastSeenStatus[session.displayId] != status {
                lastSeenStatus[session.displayId] = status
                lastStateChange[session.displayId] = now
            }
        }
        // 清掉已消失的 session
        lastSeenStatus = lastSeenStatus.filter { liveIds.contains($0.key) }
        lastStateChange = lastStateChange.filter { liveIds.contains($0.key) }
    }

    /// 根据 autoSortSessions 设置决定是否排序。
    /// 排序规则: 等待中(0) > 工作中(1) > 空闲(2);同档内按状态变化时间倒序(最近的在前)。
    private func sortedForDisplay(_ sessions: [ClaudeSession]) -> [ClaudeSession] {
        guard UserDefaults.standard.bool(forKey: Self.autoSortKey) else { return sessions }
        return sessions.sorted { a, b in
            let tierA = priorityTier(a)
            let tierB = priorityTier(b)
            if tierA != tierB { return tierA < tierB }
            let timeA = lastStateChange[a.displayId] ?? .distantPast
            let timeB = lastStateChange[b.displayId] ?? .distantPast
            return timeA > timeB
        }
    }

    /// 排序优先级分档: 数字越小越靠前。
    private func priorityTier(_ session: ClaudeSession) -> Int {
        if session.isBlocked { return 0 }   // 等待中
        if session.isBusy { return 1 }      // 工作中
        return 2                            // 空闲
    }
}
