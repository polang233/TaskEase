import SwiftUI

/// 列表与菜单栏共用的应用占用数值、占用比例和排序菜单。
/// 占用条与文字同一口径：CPU 按当前显示口径，内存为物理内存占比，GPU 为执行时间占比；
/// 磁盘和网络没有固定上限，取运行中应用合计里的占比。
@MainActor
struct AppUsage {
    let key: AppSortKey
    let scale: CPUScale
    private let diskTotal: Double
    private let networkTotal: Double

    /// 合计过小时按下限计算，避免几 KB/s 的零散读写也铺满整行。
    private static let diskFloor = 1_000_000.0
    private static let networkFloor = 100_000.0
    private static var cores: Double { Double(max(1, ProcessInfo.processInfo.activeProcessorCount)) }

    /// `apps` 为参与比较的全部运行中应用，不受搜索与系统应用筛选影响。
    init(_ key: AppSortKey, scale: CPUScale, apps: [AppReading]) {
        self.key = key
        self.scale = scale
        let running = apps.filter(\.isRunning)
        diskTotal = key == .disk ? running.reduce(0) { $0 + Self.disk($1) } : 0
        networkTotal = key == .network ? running.reduce(0) { $0 + (Self.network($1) ?? 0) } : 0
    }

    static func cpu(_ app: AppReading, scale: CPUScale) -> Double? {
        scale == .machine ? app.cpuPercent.map { $0 / cores } : app.cpuPercent
    }

    func value(_ app: AppReading) -> String {
        switch key {
        case .memory: Display.memory(app)
        case .gpu: Display.percent(app.gpuPercent)
        case .disk: Display.rate(Self.disk(app))
        case .network: Display.networkRate(Self.network(app))
        case .cpu, .name: Display.percent(Self.cpu(app, scale: scale))
        }
    }

    /// 次要一行说明当前指标的构成或占比，与占用条对应。
    func secondary(_ app: AppReading) -> String {
        switch key {
        case .cpu, .name: Display.memory(app)
        case .memory: "占物理内存 " + Display.percent(fraction(app).map { $0 * 100 })
        case .gpu: "CPU " + Display.percent(Self.cpu(app, scale: scale))
        case .disk: "读 " + Display.rate(app.readRate) + "  写 " + Display.rate(app.writeRate)
        case .network: "↓ " + Display.networkRate(app.network?.receiveRate) + "  ↑ " + Display.networkRate(app.network?.sendRate)
        }
    }

    func fraction(_ app: AppReading) -> Double? {
        guard app.isRunning else { return nil }
        switch key {
        case .cpu, .name: return Self.cpu(app, scale: scale).map { $0 / 100 }
        case .memory:
            let total = Double(ProcessInfo.processInfo.physicalMemory)
            return total > 0 && app.memoryBytes > 0 ? Double(app.memoryBytes) / total : nil
        case .gpu: return app.gpuPercent.map { $0 / 100 }
        case .disk: return Self.disk(app) / max(diskTotal, Self.diskFloor)
        case .network: return Self.network(app).map { $0 / max(networkTotal, Self.networkFloor) }
        }
    }

    private static func disk(_ app: AppReading) -> Double { app.readRate + app.writeRate }

    private static func network(_ app: AppReading) -> Double? {
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
