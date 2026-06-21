import Foundation
import Darwin

/// 通过进程树向上爬,把 claude PID 解析为宿主 app。
///
/// 设计要点:
/// - 缓存住 PID -> HostApp?(nil 也缓存,表示「确认找不到」,避免每次 poll 都重走 syscall)
/// - 失效策略:基于 PID 消失,在 `pruneCache(keepingLivePids:)` 里清掉
/// - 线程安全:`NSLock` 保护缓存;本身是同步 API,从主线程调用
final class HostAppDetector {
    private var cache: [Int: HostApp?] = [:]
    private let lock = NSLock()
    private let whitelist: [HostApp]

    init(whitelist: [HostApp] = HostApp.defaultWhitelist) {
        self.whitelist = whitelist
    }

    /// 返回 PID 对应的宿主 app。缓存命中直接返回,未命中走进程树。
    func detect(forPid pid: Int) -> HostApp? {
        lock.lock()
        if let cached = cache[pid] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let result = walkProcessTree(pid: pid)

        lock.lock()
        cache[pid] = result
        lock.unlock()
        return result
    }

    /// 清掉不在 `pids` 集合里的缓存条目。下次这些 PID 再出现会被视作全新,重新查询。
    func pruneCache(keepingLivePids pids: Set<Int>) {
        lock.lock()
        defer { lock.unlock() }
        let toRemove = Set(cache.keys).subtracting(pids)
        for pid in toRemove {
            cache.removeValue(forKey: pid)
        }
    }

    // MARK: - 进程树遍历

    private func walkProcessTree(pid: Int) -> HostApp? {
        var currentPid = pid
        var visited = Set<Int>()
        // 最多向上爬 10 层,防御性防循环(zombie / 异常进程树)
        for _ in 0..<10 {
            if visited.contains(currentPid) { return nil }
            visited.insert(currentPid)

            guard let info = pidInfo(currentPid) else { return nil }

            // 1. 直接匹配白名单
            if let app = whitelist.first(where: { $0.matches(processName: info.comm) }) {
                return app
            }

            // 2. 碰到 tmux server → 查 attached client 的宿主
            //    comm 可能是 "tmux" / "tmux: server" / "tmux: client"
            if info.comm.hasPrefix("tmux") {
                return findTmuxClientHost()
            }

            if info.ppid <= 1 { return nil }  // 到达 launchd 或 init,停止
            currentPid = info.ppid
        }
        return nil
    }

    /// 调 `tmux list-clients` 拿所有 attached client 的 PID,逐个向上爬找白名单 app。
    /// 无 client 附加 / 无匹配 → 返回 nil(用户没在前台用 tmux,合理显示"(未知)")。
    private func findTmuxClientHost() -> HostApp? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["tmux", "list-clients", "-F", "#{client_pid}"]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }

        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8), !output.isEmpty else {
            return nil
        }

        let clientPids = output.split(separator: "\n").compactMap { Int($0) }

        for clientPid in clientPids {
            if let host = walkUpToWhitelist(pid: clientPid, maxDepth: 5) {
                return host
            }
        }
        return nil
    }

    /// 从 pid 向上爬最多 maxDepth 层,找白名单命中。比 walkProcessTree 更短,
    /// 因为 tmux client → 终端的链路通常只有 1-2 跳。
    private func walkUpToWhitelist(pid: Int, maxDepth: Int) -> HostApp? {
        var current = pid
        var visited = Set<Int>()
        for _ in 0..<maxDepth {
            if visited.contains(current) { return nil }
            visited.insert(current)
            guard let info = pidInfo(current) else { return nil }
            if let app = whitelist.first(where: { $0.matches(processName: info.comm) }) {
                return app
            }
            if info.ppid <= 1 { return nil }
            current = info.ppid
        }
        return nil
    }

    private func pidInfo(_ pid: Int) -> (ppid: Int, comm: String)? {
        // 快速路径:proc_pidinfo 直接 syscall (~0.1ms)。
        // 失败时(通常是 root 拥有的进程如 /usr/bin/login)fallback 到 ps。
        if let fast = pidInfoViaProc(pid: pid) {
            return fast
        }
        return pidInfoViaPS(pid: pid)
    }

    private func pidInfoViaProc(pid: Int) -> (ppid: Int, comm: String)? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.stride)
        let ret = proc_pidinfo(Int32(pid), PROC_PIDTBSDINFO, 0, &info, size)
        guard ret > 0 else { return nil }

        let comm = withUnsafePointer(to: &info.pbi_comm) { tuplePtr -> String in
            tuplePtr.withMemoryRebound(
                to: CChar.self,
                capacity: MemoryLayout.size(ofValue: tuplePtr.pointee)
            ) { charPtr in
                String(cString: charPtr)
            }
        }

        return (Int(info.pbi_ppid), comm)
    }

    /// Fallback: 调 /bin/ps 读 ppid 和 ucomm (truncated short comm)。
    /// 慢(~10ms,subprocess 开销),但能读 root 拥有的进程。
    /// 注意:macOS `ps -o comm=` 输出完整路径(ucomm 才输出 truncated 短名,
    /// 和 `pbi_comm` 一致),用 ucomm 才能和白名单匹配。
    private func pidInfoViaPS(pid: Int) -> (ppid: Int, comm: String)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-p", "\(pid)", "-o", "ppid=,ucomm="]

        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }

        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !output.isEmpty
        else { return nil }

        guard let firstSpace = output.firstIndex(of: " "),
              let ppid = Int(output[..<firstSpace])
        else { return nil }
        let comm = String(output[output.index(after: firstSpace)...])
            .trimmingCharacters(in: .whitespaces)
        return (ppid, comm)
    }
}