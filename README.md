# CC Status

macOS 菜单栏应用，实时监控 Claude Code 的运行状态。

- 🟢 绿色 = 所有 session 空闲
- 🟡 黄色 = 有 session 正在忙碌
- ⚪ 灰色 = 未检测到 Claude Code

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
