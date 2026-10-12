import SwiftUI

/// 列表与菜单栏共用的应用占用数值、占用比例和排序菜单。
@MainActor
enum AppUsage {
    /// 满格参考：CPU 单核口径为一个核心、整机口径为全部核心；内存为物理内存总量；GPU 100%；
    /// 磁盘 100 MB/s；网络 10 MB/s。
    private static let diskScale = 100_000_000.0
    private static let networkScale = 10_000_000.0
    private static var cores: Double { Double(max(1, ProcessInfo.processInfo.activeProcessorCount)) }

    static func cpu(_ app: AppReading, scale: CPUScale) -> Double? {
        scale == .machine ? app.cpuPercent.map { $0 / cores } : app.cpuPercent
    }

    static func value(_ app: AppReading, _ key: AppSortKey, scale: CPUScale) -> String {
        switch key {
        case .memory: Display.memory(app)
        case .gpu: Display.percent(app.gpuPercent)
        case .disk: Display.rate(app.readRate + app.writeRate)
        case .network: Display.networkRate(networkTotal(app))
        case .cpu, .name: Display.percent(cpu(app, scale: scale))
        }
    }

    static func secondary(_ app: AppReading, _ key: AppSortKey, scale: CPUScale) -> String {
        switch key {
        case .cpu, .name: Display.memory(app)
        default: "CPU " + Display.percent(cpu(app, scale: scale))
        }
    }

    static func fraction(_ app: AppReading, _ key: AppSortKey, scale: CPUScale) -> Double? {
        guard app.isRunning else { return nil }
        switch key {
        case .cpu, .name: return cpu(app, scale: scale).map { $0 / 100 }
        case .memory:
            let total = Double(ProcessInfo.processInfo.physicalMemory)
            return total > 0 && app.memoryBytes > 0 ? Double(app.memoryBytes) / total : nil
        case .gpu: return app.gpuPercent.map { $0 / 100 }
        case .disk: return (app.readRate + app.writeRate) / diskScale
        case .network: return networkTotal(app).map { $0 / networkScale }
        }
    }

    private static func networkTotal(_ app: AppReading) -> Double? {
        app.network.map { ($0.receiveRate ?? 0) + ($0.sendRate ?? 0) }
    }
}

/// 整行背景的占用填充：从左向右按占比铺开，颜色由绿渐变到对应档位，尾部转淡。
struct UsageFill: View {
    let fraction: Double?

    var body: some View {
        GeometryReader { proxy in
            let value = min(1, max(0, fraction ?? 0))
            if fraction != nil && value > 0 {
                let colors = MetricPalette.gradient(upTo: value)
                RoundedRectangle(cornerRadius: 7)
                    .fill(LinearGradient(colors: colors.map { $0.opacity(0.24) } + [colors.last!.opacity(0.08)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(8, proxy.size.width * value))
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// 带边框的排序菜单；管理窗口中同时放“显示系统应用”，与排序共用一个入口。
struct SortMenu: View {
    @Bindable var model: AppModel
    var showsSystemToggle = false

    var body: some View {
        Menu {
            Picker("排序", selection: Binding(get: { model.effectiveSortKey },
                                            set: { key in model.updatePreferences { $0.sortKey = key } })) {
                ForEach(model.sortKeys, id: \.self) { Text($0.title).tag($0) }
            }.pickerStyle(.inline)
            if showsSystemToggle && model.applicationList == .running {
                Divider()
                Toggle("显示系统应用", isOn: Binding(get: { model.preferences.showSystemApps },
                    set: { value in model.updatePreferences { $0.showSystemApps = value } }))
                    .accessibilityIdentifier("show-system-apps")
            }
        } label: {
            Label("按 \(model.effectiveSortKey.title)", systemImage: "arrow.up.arrow.down")
                .labelStyle(.titleAndIcon)
        }
        .menuStyle(.button).buttonStyle(.bordered).controlSize(.small).fixedSize()
        .pointingHand().help("排序与筛选").accessibilityIdentifier("app-sort")
    }
}
