import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let monitor = ClaudeMonitor()
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

    private enum IconState {
        case error
        case empty
        case blocked
        case working
        case idle
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
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
            self.sessions = sessions
            self.lastError = nil
        case .failure(let error):
            self.lastError = error.localizedDescription
        }

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

        // 等待中的 session：把项目名追加到图标后面
        if newState == .blocked {
            let blockedNames = sessions
                .filter { $0.isBlocked }
                .map { $0.projectName }
            button.title = blockedNames.joined(separator: ", ")
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
            for session in sessions {
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

                let restText = " \(session.projectName) — \(session.statusDisplay) (\(session.durationDisplay))"
                let attributedTitle = NSMutableAttributedString()
                attributedTitle.append(NSAttributedString(
                    string: statusDot,
                    attributes: [.foregroundColor: statusColor, .font: NSFont.systemFont(ofSize: 13, weight: .bold)]
                ))
                attributedTitle.append(NSAttributedString(string: restText))

                let item = NSMenuItem()
                item.attributedTitle = attributedTitle
                item.isEnabled = false
                menu.addItem(item)
            }
        }

        menu.addItem(NSMenuItem.separator())

        let refreshItem = NSMenuItem(title: "刷新", action: #selector(refresh), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let quitItem = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Actions

    @objc private func refresh() {
        poll()
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
}
