# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

CCStatus 是一个原生 macOS 菜单栏应用，用于实时监控 Claude Code 的运行状态。通过监听 `~/.claude/sessions/` 目录下的 JSON 文件变化，在菜单栏显示当前所有 Claude Code 会话的状态图标和项目名称。

## 常用命令

```bash
swift build                    # 构建（debug）
swift build -c release         # 构建（release）
swift run                      # 运行
./scripts/build-app.sh         # 打包为 .app bundle（ad-hoc 签名）
./scripts/build-release.sh     # 多架构 release 构建（arm64 + x86_64）
./scripts/build-release.sh --dmg  # release 构建 + DMG 打包
open CCStatus.app              # 打开打包后的应用
```

项目无测试和代码检查配置。

## 架构

使用 Swift Package Manager 构建，纯 AppKit 实现，零外部依赖，目标平台 macOS 13+。

**核心流程：** `main.swift` → `AppDelegate` → `FileWatcher` 监听 `~/.claude/sessions/` → 触发 `FileSessionReader.fetchSessions()` 读取 JSON 文件 → 解码为 `[ClaudeSession]` → `HostAppDetector` 解析宿主应用 → 更新菜单栏图标和菜单。

**源文件结构：**

- `main.swift` — 手动创建 NSApplication 生命周期（无 @main、无 SwiftUI）
- `AppDelegate.swift` — 中央控制器：持有 NSStatusItem、FileWatcher，负责 UI 更新、菜单构建、桌面通知、睡眠/唤醒处理
- `FileWatcher.swift` — FSEventStream 监听目录变化，100ms 防抖触发 poll
- `FileSessionReader.swift` — 读取 `~/.claude/sessions/*.json` 文件，解码为 `ClaudeSession` 数组
- `SessionModel.swift` — `ClaudeSession` Codable 模型，包含 `pid`、`cwd`、`state`、`status`、`name` 等字段，以及派生属性（`projectName`、`statusDisplay`、`isBusy`、`isBlocked`）
- `HostApp.swift` — `HostApp` 结构体定义和已知终端/IDE 白名单（Kitty、iTerm、Terminal、VSCode、Cursor、Zed、Ghostty、Warp、Alacritty）
- `HostAppDetector.swift` — 从 PID 向上遍历进程树识别宿主应用，支持 tmux，带缓存和线程安全
- `AppActivator.swift` — 三级策略激活宿主应用到前台（NSRunningApplication → NSAppleScript → System Events）
- `PreferencesWindowController.swift` — 纯代码 NSWindow 配置面板（通知、菜单栏、列表三组设置），三个状态开关水平排列带 SF Symbol 图标
- `Info.plist` — `LSUIElement=true`（无 Dock 图标，仅菜单栏显示）

## 关键设计

- **文件监听替代子进程轮询**：早期版本通过子进程执行 `claude agents --json`，现已改为直接读取 `~/.claude/sessions/` 目录下的 JSON 文件，由 FSEventStream 触发更新
- **桌面通知**：追踪每个 session 的 `lastSeenBlocked` 状态，仅在从非 blocked 转为 blocked 且宿主应用不在前台时触发通知。仅在 .app bundle 模式下生效（`swift run` 时跳过）
- **"dialog open" 排除**：`status` 为 `waiting` 且 `waitingFor` 包含 "dialog open" 时不视为 blocked，避免浏览菜单时误触发通知
- **菜单栏图标五态**：error（灰色空心）、empty（灰色空心）、blocked（橙色实心）、working（绿色实心+呼吸动画）、idle（灰色实心）
- **UserDefaults 配置项**：`autoSortSessions`、`showWaitingNameInMenuBar`、`showRunningNameInMenuBar`、`showIdleNameInMenuBar`、`maxNameLengthInMenuBar`、`desktopNotificationsEnabled`

## 注意事项

- 界面文案使用中文（状态显示、时间格式等）
- 使用 SF Symbols（`circle`、`circle.fill`）作为图标
- `fetchSessions()` 使用 `Result<[ClaudeSession], MonitorError>` 进行错误处理
- 桌面通知需要 ad-hoc 签名才能正常工作（`codesign --force --sign -`）
- 宿主应用白名单在 `HostApp.swift` 中维护，新增终端/IDE 只需添加一个 `HostApp` 条目
