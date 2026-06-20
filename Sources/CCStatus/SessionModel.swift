import Foundation

struct ClaudeSession: Codable, Identifiable {
    let pid: Int
    let cwd: String
    let kind: String
    let startedAt: Int64
    let sessionId: String
    let status: String

    var id: String { sessionId }

    var projectName: String {
        URL(fileURLWithPath: cwd).lastPathComponent
    }

    var statusDisplay: String {
        switch status {
        case "busy": return "忙碌"
        case "idle": return "空闲"
        default: return status
        }
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

    var isBusy: Bool { status == "busy" }
}
