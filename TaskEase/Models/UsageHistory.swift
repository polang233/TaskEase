import Foundation

/// 一次采样中某个应用的各项读数；缺失的读数为 nil。CPU 按单核口径保存，显示时再换算。
/// `time` 是折线图的横轴：只累计实际记录的时间，暂停采样的空档不占位置。
struct UsagePoint: Equatable, Sendable {
    let date: Date
    var time: TimeInterval = 0
    var cpu: Double?
    var memory: Double?
    var gpu: Double?
    var read: Double?
    var write: Double?
    var receive: Double?
    var send: Double?
}

/// 每个运行中应用最近几分钟的采样，用于详情里的折线图。
/// 只在已有的采样到达时追加，没有额外计时器；应用退出后清除其记录。
/// 窗口不刷新期间没有记录，回来后从离开时的位置接着画，曲线保持连贯。
struct UsageHistory: Sendable {
    /// 保留时长与点数上限；1 秒刷新时约五分钟三百点。
    static let retention: TimeInterval = 300
    static let capacity = 300

    private(set) var series: [String: [UsagePoint]] = [:]

    /// `step` 为本次采样的正常间隔；与上一点相隔超过约 2.5 个间隔视为中途暂停，只前进一个间隔。
    /// `removingOthers` 为 false 时只追加给定应用，用于只扫描受控应用的后台检查。
    mutating func record(_ apps: [AppReading], at date: Date, step: TimeInterval, removingOthers: Bool = true) {
        var live = Set<String>()
        for app in apps where app.isRunning {
            live.insert(app.id)
            var points = series[app.id] ?? []
            var time: TimeInterval = 0
            if let last = points.last {
                let elapsed = date.timeIntervalSince(last.date)
                time = last.time + (elapsed > 0 && elapsed <= step * 2.5 ? elapsed : step)
            }
            points.append(UsagePoint(date: date, time: time, cpu: app.cpuPercent, memory: Double(app.memoryBytes),
                                     gpu: app.totalGPUPercent, read: app.readRate, write: app.writeRate,
                                     receive: app.network?.receiveRate, send: app.network?.sendRate))
            if let first = points.firstIndex(where: { $0.time >= time - Self.retention }), first > 0 {
                points.removeFirst(first)
            }
            if points.count > Self.capacity { points.removeFirst(points.count - Self.capacity) }
            series[app.id] = points
        }
        if removingOthers { series = series.filter { live.contains($0.key) } }
    }

    func points(for id: String) -> [UsagePoint] { series[id] ?? [] }

    /// 预览与界面测试用的固定曲线：以各应用当前读数为基准做平缓起伏，不含随机数。
    mutating func seedFixture(from apps: [AppReading], now: Date, interval: TimeInterval = 3, count: Int = 55) {
        for app in apps where app.isRunning {
            series[app.id] = (0..<count).map { index in
                let wave = 1 + 0.35 * sin(Double(index) / 5) + 0.15 * sin(Double(index) / 1.7)
                let ramp = 0.6 + 0.4 * Double(index) / Double(count - 1)
                return UsagePoint(date: now.addingTimeInterval(-interval * Double(count - 1 - index)),
                                  time: interval * Double(index), cpu: app.cpuPercent.map { $0 * wave }, memory: Double(app.memoryBytes) * ramp,
                                  gpu: app.totalGPUPercent.map { $0 * wave }, read: app.readRate * wave,
                                  write: app.writeRate * (2 - wave), receive: app.network?.receiveRate.map { $0 * wave },
                                  send: app.network?.sendRate.map { $0 * (2 - wave) })
            }
        }
    }
}
