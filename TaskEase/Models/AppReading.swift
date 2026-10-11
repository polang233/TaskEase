import Foundation

/// 整机读数；内存为物理占用，网络速度按活动物理网卡合计。
struct SystemReading: Sendable {
    var cpuPercent: Double?
    var gpuPercent: Double?
    var thermalLabel: String = "正常"
    var memory: SystemMemoryReading?
    var network: SystemNetworkReading?
    var temperatureCelsius: Double?
}

/// 应用与自有辅助进程的合计占用，兼容未运行的已配置应用。
struct AppReading: Identifiable, Sendable {
    let id: String
    let name: String
    let bundlePaths: [String]
    let primaryPIDs: Set<Int32>
    var targets: [ControlTarget]
    var samples: [ProcessSample]
    var cpuPercent: Double?
    var memoryBytes: UInt64
    var readRate: Double
    var writeRate: Double
    var canControl: Bool
    var isHidden: Bool
    var status: RuleStatus = .unmanaged
    var wakeupRate: Double = 0
    var isRunning = true
    var network: NetworkReading?
    var processNetwork: [ProcessIdentity: NetworkReading] = [:]

    var isSystemApp: Bool {
        ApplicationScope.isSystem(id: id, roots: bundlePaths)
    }

    static func offline(id: String, metadata: SavedApplication?) -> AppReading {
        AppReading(id: id, name: metadata?.name ?? id,
                   bundlePaths: metadata?.bundlePaths ?? [], primaryPIDs: [],
                   targets: [], samples: [], cpuPercent: nil, memoryBytes: 0,
                   readRate: 0, writeRate: 0, canControl: false, isHidden: false,
                   status: .notRunning, isRunning: false)
    }
}

enum ApplicationScope {
    static func isSystem(id: String, roots: [String]) -> Bool {
        roots.isEmpty ? id.hasPrefix("com.apple.") : roots.contains { $0.hasPrefix("/System/") }
    }
}

/// 名称和路径单独保存，应用退出后仍可展示和编辑规则。
struct SavedApplication: Codable, Equatable, Sendable {
    let name: String
    let bundlePaths: [String]

    init(name: String, bundlePaths: [String]) {
        self.name = name
        self.bundlePaths = bundlePaths
    }

    init(_ app: AppReading) {
        name = app.name
        bundlePaths = app.bundlePaths
    }
}

enum ApplicationList: String, CaseIterable, Sendable {
    case running, configured

    var title: String {
        switch self {
        case .running: "运行中的应用"
        case .configured: "已配置规则"
        }
    }
}
