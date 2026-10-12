import Foundation

/// 系统概览的指标呈现方式，只影响外观，不改变采样。
enum MetricDisplayStyle: String, Codable, CaseIterable, Sendable {
    case number, ring, bar

    var title: String {
        switch self {
        case .number: "数字"
        case .ring: "圆环"
        case .bar: "进度条"
        }
    }
}

/// 应用列表排序依据；网络仅在显示应用网络速度时可选。
enum AppSortKey: String, Codable, CaseIterable, Sendable {
    case cpu, memory, gpu, disk, network, name

    var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "内存"
        case .gpu: "GPU"
        case .disk: "磁盘"
        case .network: "网络"
        case .name: "名称"
        }
    }
}

/// 应用 CPU 的显示口径。规则中的 CPU 上限始终按单核计算，不受此选项影响。
enum CPUScale: String, Codable, CaseIterable, Sendable {
    case core, machine

    var title: String {
        switch self {
        case .core: "单核"
        case .machine: "整机"
        }
    }
}
