import Foundation

/// 整机读数；内存为物理占用，网络速度按活动物理网卡合计。
struct SystemReading: Equatable, Sendable {
    var cpuPercent: Double?
    var gpuPercent: Double?
    var thermal: ThermalLevel = .nominal
    var memory: SystemMemoryReading?
    var network: SystemNetworkReading?
    var temperatureCelsius: Double?
    /// GPU 占用最高的来源，含其他用户的系统进程（如 WindowServer）；按占用从高到低，仅显示采样读取。
    var gpuSources: [GPUSource] = []
}

/// 一个 GPU 占用来源：已识别的应用按应用合并，其余按进程名列出。
struct GPUSource: Equatable, Sendable {
    let name: String
    let percent: Double
    /// `percent` 中按估算归入的窗口合成部分。
    var compositing: Double = 0
    /// 系统窗口合成进程；屏幕共享、录屏和窗口特效的 GPU 时间都记在它名下。
    var isWindowServer: Bool { name == "WindowServer" }
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
    /// 自有进程 GPU 执行时间占墙钟时间的比例，仅显示采样读取。
    var gpuPercent: Double? = nil
    /// 应用正在显示视频画面时，WindowServer 为合成其窗口花费的 GPU，按可见窗口面积估算；其余情况为 nil。
    var compositingGPUPercent: Double? = nil
    /// 自身 GPU 加上估算的窗口合成，用于 GPU 排序、数值与占用条。
    var totalGPUPercent: Double? {
        guard gpuPercent != nil || compositingGPUPercent != nil else { return nil }
        return min(100, (gpuPercent ?? 0) + (compositingGPUPercent ?? 0))
    }
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
        case .running: String(localized: "list.running")
        case .configured: String(localized: "list.configured")
        }
    }
}
