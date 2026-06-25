import Foundation

struct ClaudeSession: Codable {
    let pid: Int?
    let cwd: String
    let kind: String
    let startedAt: Int64
    let sessionId: String?
    let status: String?
    let state: String?
    let id: String?
    let name: String?
    let waitingFor: String?
    let entrypoint: String?

    /// 对于 claude-vscode 类型的会话，session 文件本身不写 status/state，
    /// 由 FileSessionReader 通过 ~/.claude/projects/<proj>/<sessionId>.jsonl 的 mtime 推断后注入。
    /// nil 表示未推断（非 vscode 会话），true=最近活动，false=较久未活动。
    var vscodeInferredBusy: Bool? = nil

    private enum CodingKeys: String, CodingKey {
        case pid, cwd, kind, startedAt, sessionId, status, state, id, name, waitingFor, entrypoint
    }

    var displayId: String { id ?? sessionId ?? "\(pid ?? 0)" }

    var isVSCodeEntrypoint: Bool { entrypoint == "claude-vscode" }

    var projectName: String {
        URL(fileURLWithPath: cwd).lastPathComponent
    }

    var statusDisplay: String {
        // claude-vscode 会话：用 jsonl mtime 推断的活动态优先（status/state 在此模式下不存在）
        if isVSCodeEntrypoint, let busy = vscodeInferredBusy {
            return busy ? NSLocalizedString("工作中", comment: "") : NSLocalizedString("空闲", comment: "")
        }
        // 优先使用 state 字段（更全面）
        if let state = state {
            switch state {
            case "working": return NSLocalizedString("工作中", comment: "")
            case "blocked": return NSLocalizedString("需要输入", comment: "")
            case "done": return NSLocalizedString("已完成", comment: "")
            case "failed": return NSLocalizedString("失败", comment: "")
            case "stopped": return NSLocalizedString("已停止", comment: "")
            default: return state
            }
        }
        // 回退到 status 字段
        if let status = status {
            switch status {
            case "busy": return NSLocalizedString("工作中", comment: "")
            case "waiting":
                if waitingFor == "dialog open" { return NSLocalizedString("浏览中", comment: "") }
                return waitingFor ?? NSLocalizedString("等待中", comment: "")
            case "idle": return NSLocalizedString("空闲", comment: "")
            default: return status
            }
        }
        // 无 status/state 的 session（如 claude-vscode entrypoint）当作空闲处理
        return NSLocalizedString("空闲", comment: "")
    }

    var durationDisplay: String {
        let elapsed = Int(Date().timeIntervalSince1970 * 1000) - Int(startedAt)
        let seconds = elapsed / 1000
        if seconds < 60 { return String(format: NSLocalizedString("%d秒", comment: ""), seconds) }
        let minutes = seconds / 60
        if minutes < 60 { return String(format: NSLocalizedString("%d分钟", comment: ""), minutes) }
        let hours = minutes / 60
        let remainMinutes = minutes % 60
        return String(format: NSLocalizedString("%d小时%d分钟", comment: ""), hours, remainMinutes)
    }

    /// waitingFor 为这些值时，不算"真正需要用户输入"，而是用户主动打开了 UI
    private static let ignorableWaitingReasons: Set<String> = ["dialog open"]

    var isBusy: Bool {
        // claude-vscode：mtime 推断
        if isVSCodeEntrypoint, let busy = vscodeInferredBusy {
            return busy
        }
        // 使用 state 字段判断
        if let state = state {
            return state == "working" || state == "blocked"
        }
        // 回退到 status 字段：busy 或 waiting（排除 dialog open 等非真正等待的情况）
        if status == "busy" { return true }
        if status == "waiting" { return !Self.ignorableWaitingReasons.contains(waitingFor ?? "") }
        return false
    }

    var isBlocked: Bool {
        if state == "blocked" { return true }
        // status 为 waiting 时，排除 dialog open 等非真正等待的情况
        if status == "waiting" { return !Self.ignorableWaitingReasons.contains(waitingFor ?? "") }
        return false
    }
}

extension ClaudeSession: Identifiable {
    // 使用 displayId 作为 Identifiable 的 id
    // 注意：这里会覆盖结构体中的 id 属性
}
