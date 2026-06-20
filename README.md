# CC Status

macOS 菜单栏应用，实时监控 Claude Code 的运行状态。通过轮询 `claude agents --json` 命令，在菜单栏显示当前所有 Claude Code 会话的状态图标。

## 状态指示

| 图标 | 颜色 | 状态 |
|------|------|------|
| ● | 🟠 橙色 | 有 session 等待输入（需要回复或授权） |
| ● | 🟢 绿色 | 有 session 正在运行（图标会呼吸脉动） |
| ● | ⚪ 灰色 | 所有 session 空闲 |
| ○ | 灰色 | 未检测到 Claude Code 或无活跃 session |

**多 session 优先级**：等待 > 运行 > 空闲 > 未检测到。

## 监控字段

应用通过 `claude agents --json` 读取以下字段：

- `state` — 会话状态：`working` / `blocked` / `done` / `failed` / `stopped`
- `status` — 进程状态：`busy` / `waiting` / `idle`（仅进程存活时存在）
- `waitingFor` — 当 `status` 为 `waiting` 时的具体原因
- `pid` / `sessionId` / `id` / `name` / `startedAt` / `cwd` / `kind`

没有 `status` 字段的会话（进程已退出）会被自动过滤。

## 构建

```bash
# 开发
swift build

# 运行
swift run

# 打包为 .app
./scripts/build-app.sh
open CCStatus.app
```

## 依赖

- macOS 13+
- Xcode Command Line Tools
- Claude Code CLI (`claude` 命令)
