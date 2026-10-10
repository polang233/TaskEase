import Foundation

/// 系统进程网络计数，只保留字节数，不保存连接地址或传输内容。
struct NetworkByteCount: Equatable, Sendable {
    let received: UInt64
    let sent: UInt64
}

struct NetworkReading: Equatable, Sendable {
    let receiveRate: Double?
    let sendRate: Double?
    let sampledProcesses: Int
}

struct NetworkRates: Sendable {
    let applications: [String: NetworkReading]
    let processes: [ProcessIdentity: NetworkReading]
}

/// 网络采样能力与控制权限分别显示，读取流量不会赋予阻断权限。
enum NetworkMonitorStatus: Equatable, Sendable {
    case disabled
    case available
    case unavailable(String)

    var message: String {
        switch self {
        case .disabled: "网络监控已关闭"
        case .available: "系统网络统计"
        case .unavailable(let reason): reason
        }
    }
}
