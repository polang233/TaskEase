import Foundation

/// PID 可能被复用，控制时同时验证所属用户和启动时间。
struct ProcessIdentity: Hashable, Codable, Sendable {
    let pid: Int32
    let uid: UInt32
    let startSeconds: UInt64
    let startMicroseconds: UInt64
}

/// 一次原生采样的累计计数，通过相邻快照计算占用。
struct ProcessSample: Sendable {
    let identity: ProcessIdentity
    let parentPID: Int32
    let status: UInt32
    let cpuTicks: UInt64
    let memoryBytes: UInt64
    let readBytes: UInt64
    let writeBytes: UInt64
    let wakeups: UInt64
}

/// 可控制成员的完整身份与路径，作为控制边界的验证依据。
struct ControlTarget: Hashable, Codable, Sendable {
    let identity: ProcessIdentity
    let executablePath: String
    let bundlePath: String
}

/// 一个应用交给工作进程的控制：`mode` 为 off、budget 或 suspend，`background` 表示降低优先级，可与 CPU 上限叠加。
struct ControlGroup: Codable, Sendable {
    let bundleID: String
    let mode: ControlMode
    var background: Bool = false
    let cpuPercent: Double
    let targets: [ControlTarget]
}

struct ControlMessage: Codable, Sendable {
    let groups: [ControlGroup]
    var shutdown: Bool = false
}

struct WorkerEvent: Codable, Sendable {
    let kind: String
    let message: String
    var processCount: Int = 0
}

/// 工作进程施加的暂停与后台优先级归属，用于异常恢复。
struct RecoveryRecord: Codable, Sendable {
    let worker: ProcessIdentity
    let controller: ProcessIdentity
    var background: [ControlTarget] = []
    var suspension: [ControlTarget] = []
}
