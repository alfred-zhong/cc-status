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

    var displayId: String { id ?? sessionId ?? "\(pid ?? 0)" }

    var projectName: String {
        URL(fileURLWithPath: cwd).lastPathComponent
    }

    var statusDisplay: String {
        // 优先使用 state 字段（更全面）
        if let state = state {
            switch state {
            case "working": return "工作中"
            case "blocked": return "需要输入"
            case "done": return "已完成"
            case "failed": return "失败"
            case "stopped": return "已停止"
            default: return state
            }
        }
        // 回退到 status 字段
        if let status = status {
            switch status {
            case "busy": return "工作中"
            case "waiting": return waitingFor ?? "等待中"
            case "idle": return "空闲"
            default: return status
            }
        }
        // 不应该到这里，因为已过滤无 status 的会话
        return status ?? state ?? "未知"
    }

    var durationDisplay: String {
        let elapsed = Int(Date().timeIntervalSince1970 * 1000) - Int(startedAt)
        let seconds = elapsed / 1000
        if seconds < 60 { return "\(seconds)秒" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)分钟" }
        let hours = minutes / 60
        let remainMinutes = minutes % 60
        return "\(hours)小时\(remainMinutes)分钟"
    }

    var isBusy: Bool {
        // 使用 state 字段判断
        if let state = state {
            return state == "working" || state == "blocked"
        }
        // 回退到 status 字段：busy 或 waiting（waiting 意味着需要输入）
        return status == "busy" || status == "waiting"
    }

    var isBlocked: Bool {
        // state 为 blocked，或 status 为 waiting（waiting 意味着需要输入）
        return state == "blocked" || status == "waiting"
    }
}

extension ClaudeSession: Identifiable {
    // 使用 displayId 作为 Identifiable 的 id
    // 注意：这里会覆盖结构体中的 id 属性
}
