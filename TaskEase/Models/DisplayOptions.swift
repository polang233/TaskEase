import Foundation

/// 系统概览的指标呈现方式，只影响外观，不改变采样。
enum MetricDisplayStyle: String, Codable, CaseIterable, Sendable {
    case number, ring, bar

    var title: String {
        switch self {
        case .number: String(localized: "style.number")
        case .ring: String(localized: "style.ring")
        case .bar: String(localized: "style.bar")
        }
    }
}

/// 应用列表排序依据；网络仅在显示应用网络速度时可选。
enum AppSortKey: String, Codable, CaseIterable, Sendable {
    case cpu, memory, gpu, disk, network, name

    var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: String(localized: "metric.memory")
        case .gpu: "GPU"
        case .disk: String(localized: "sort.disk")
        case .network: String(localized: "sort.network")
        case .name: String(localized: "sort.name")
        }
    }
}

/// 应用 CPU 的显示口径。规则中的 CPU 上限始终按单核计算，不受此选项影响。
enum CPUScale: String, Codable, CaseIterable, Sendable {
    case core, machine

    var title: String {
        switch self {
        case .core: String(localized: "cpuScale.core")
        case .machine: String(localized: "cpuScale.machine")
        }
    }
}
