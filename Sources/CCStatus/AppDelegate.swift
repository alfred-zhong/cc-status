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

        // Poll every 5 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.poll()
        }
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
        } else if sessions.contains(where: { $0.state == "blocked" }) {
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
                if session.state == "blocked" {
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
        NSApplication.shared.terminate(nil)
    }
}
