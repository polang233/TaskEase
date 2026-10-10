import Foundation

/// PID alone can be reused. Every control operation also checks the user and start time.
struct ProcessIdentity: Hashable, Codable, Sendable {
    let pid: Int32
    let uid: UInt32
    let startSeconds: UInt64
    let startMicroseconds: UInt64
}

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

struct ControlTarget: Hashable, Codable, Sendable {
    let identity: ProcessIdentity
    let executablePath: String
    let bundlePath: String
}

struct ControlGroup: Codable, Sendable {
    let bundleID: String
    let mode: ControlMode
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

struct RecoveryRecord: Codable, Sendable {
    let worker: ProcessIdentity
    let controller: ProcessIdentity
    var background: [ControlTarget] = []
    var suspension: [ControlTarget] = []
}
