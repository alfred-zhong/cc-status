import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let monitor = ClaudeMonitor()
    private var timer: Timer?
    private var sessions: [ClaudeSession] = []
    private var lastError: String?

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

        if !monitor.isAvailable || lastError != nil {
            // Claude not found or error - 灰色空心
            image = NSImage(systemSymbolName: "circle", accessibilityDescription: "CC Status")!
            tintColor = .systemGray
        } else if sessions.isEmpty {
            // No sessions - 灰色空心
            image = NSImage(systemSymbolName: "circle", accessibilityDescription: "CC Status")!
            tintColor = .systemGray
        } else if sessions.contains(where: { $0.state == "blocked" }) {
            // Any session waiting for input - 橙色实心
            image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "CC Status")!
            tintColor = .systemOrange
        } else if sessions.contains(where: { $0.isBusy }) {
            // Any session working - 绿色实心
            image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "CC Status")!
            tintColor = .systemGreen
        } else {
            // All idle - 灰色实心
            image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "CC Status")!
            tintColor = .systemGray
        }

        let tintedImage = NSImage(size: image.size, flipped: false) { rect in
            tintColor.set()
            rect.fill()
            image.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1.0)
            return true
        }
        tintedImage.isTemplate = false
        button.image = tintedImage
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
                let statusDot: String
                if session.state == "blocked" {
                    statusDot = "🟠"  // 等待输入 - 橙色
                } else if session.isBusy {
                    statusDot = "🟢"  // 运行中 - 绿色
                } else {
                    statusDot = "⚫"  // 空闲 - 灰色
                }
                let title = "\(statusDot) \(session.projectName) — \(session.statusDisplay) (\(session.durationDisplay))"
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
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
        NSApplication.shared.terminate(nil)
    }
}
