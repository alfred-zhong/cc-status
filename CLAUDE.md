# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

CCStatus 是一个原生 macOS 菜单栏应用，用于实时监控 Claude Code 的运行状态。通过轮询 `claude agents --json` 命令，在菜单栏显示当前所有 Claude Code 会话的状态图标（绿色=全部空闲，橙色=有会话忙碌，灰色=未检测到）。

## 常用命令

```bash
swift build                    # 构建（debug）
swift build -c release         # 构建（release）
swift run                      # 运行
./scripts/build-app.sh         # 打包为 .app bundle
open CCStatus.app              # 打开打包后的应用
```

项目无测试和代码检查配置。

## 架构

使用 Swift Package Manager 构建，纯 AppKit 实现，零外部依赖，目标平台 macOS 13+。

**核心流程：** `main.swift` → `AppDelegate` → 每 5 秒调用 `ClaudeMonitor.fetchSessions()` → 解码 JSON 为 `[ClaudeSession]` → 更新菜单栏图标和菜单。

**源文件结构：**

- `main.swift` — 手动创建 NSApplication 生命周期（无 @main、无 SwiftUI）
- `AppDelegate.swift` — 持有 NSStatusItem 和 ClaudeMonitor，负责 UI 更新和定时轮询
- `ClaudeMonitor.swift` — 探测 claude CLI 路径（`/opt/homebrew/bin/claude` 或 `/usr/local/bin/claude`，回退到 `zsh -l -c "which claude"`），通过子进程执行 `claude agents --json`
- `SessionModel.swift` — `ClaudeSession` Codable 模型，包含 `pid`、`cwd`、`kind`、`startedAt`、`sessionId`、`status`，以及派生属性（`projectName`、`statusDisplay`、`durationDisplay`、`isBusy`）
- `Info.plist` — `LSUIElement=true`（无 Dock 图标，仅菜单栏显示）

## 注意事项

- 界面文案使用中文（状态显示、时间格式等）
- 使用 SF Symbols（`circle`、`circle.fill`）作为图标
- `fetchSessions()` 使用 `Result<[ClaudeSession], MonitorError>` 进行错误处理
- `isPolling` 布尔值防止并发轮询
