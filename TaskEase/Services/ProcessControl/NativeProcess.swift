import Foundation
import AppKit
import Darwin

/// 封装原生进程读取与控制，每次写操作验证进程身份及归属。
enum NativeProcess {
    static let ticksPerSecond = te_ticks_per_second()
    static var now: UInt64 { te_now() }
    static func seconds(since ticks: UInt64) -> Double { Double(now &- ticks) / ticksPerSecond }
    static func identity(_ pid: Int32) -> ProcessIdentity? {
        var raw = TEProcessStats()
        guard te_process_identity(pid, &raw) != 0 else { return nil }
        return ProcessIdentity(pid: raw.pid, uid: raw.uid,
                               startSeconds: raw.startSeconds, startMicroseconds: raw.startMicroseconds)
    }
    static func sample(_ pid: Int32) -> ProcessSample? {
        var raw = TEProcessStats()
        guard te_process_stats(pid, &raw) != 0 else { return nil }
        return ProcessSample(identity: ProcessIdentity(pid: raw.pid, uid: raw.uid,
                             startSeconds: raw.startSeconds, startMicroseconds: raw.startMicroseconds),
                             parentPID: raw.parentPid, status: raw.status, cpuTicks: raw.cpuTicks,
                             memoryBytes: raw.physicalBytes, readBytes: raw.diskReadBytes,
                             writeBytes: raw.diskWriteBytes, wakeups: raw.interruptWakeups)
    }
    static func path(_ pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        guard te_process_path(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return URL(fileURLWithPath: String(decoding: bytes, as: UTF8.self)).resolvingSymlinksInPath().path
    }
    static func pids() -> [Int32] {
        var buffer = [Int32](repeating: 0, count: 8192)
        let count = te_list_pids(&buffer, Int32(buffer.count * MemoryLayout<Int32>.stride))
        return count > 0 ? Array(buffer.prefix(Int(count))) : []
    }
    /// 控制前核对 UID、启动时间、可执行路径和应用 bundle 归属。
    static func matches(_ target: ControlTarget) -> Bool {
        guard target.identity.pid > 1, target.identity.uid == geteuid(),
              let current = identity(target.identity.pid), current == target.identity,
              let executable = path(current.pid), executable == target.executablePath else { return false }
        let root = URL(fileURLWithPath: target.bundlePath).resolvingSymlinksInPath().path
        return root.hasSuffix(".app") && !root.hasPrefix("/System/") &&
            executable.hasPrefix(root + "/Contents/")
    }
    @discardableResult static func background(_ target: ControlTarget, enabled: Bool) -> Bool {
        guard enabled ? matches(target) : identity(target.identity.pid) == target.identity else { return false }
        return te_set_background(target.identity.pid, target.identity.startSeconds,
                                 target.identity.startMicroseconds, enabled ? 1 : 0) == 0
    }
    /// 新增控制验证完整路径；恢复只核对身份，让路径变化后的成员也能恢复。
    @discardableResult static func signal(_ target: ControlTarget, number: Int32) -> Bool {
        guard number == SIGCONT ? identity(target.identity.pid) == target.identity : matches(target) else { return false }
        return te_signal_process(target.identity.pid, target.identity.startSeconds,
                                 target.identity.startMicroseconds, number) == 0
    }
    static func isAlive(_ identity: ProcessIdentity) -> Bool {
        guard let current = sample(identity.pid) else { return false }
        return current.identity == identity && current.status != 5
    }
}
