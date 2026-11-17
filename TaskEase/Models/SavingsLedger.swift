import Foundation

/// 一个应用在后台、未受限制时的平均占用，作为节省估算与智能建议的基线。
/// 按观察时长加权，超过窗口后新读数逐渐替换旧值，近似最近约 10 分钟的后台平均。
/// CPU 为单核口径（100% 为一个核心满载）；GPU 含估算的窗口合成，只来自显示采样。
struct UsageBaseline: Codable, Equatable, Sendable {
    var cpuPercent: Double = 0
    var cpuSeconds: TimeInterval = 0
    var gpuPercent: Double = 0
    var gpuSeconds: TimeInterval = 0
    /// 观察到的最大窗口合成占比，用于判断应用是否在持续显示画面。
    var compositingPercent: Double = 0
    var updatedAt: Date

    static let window: TimeInterval = 600
    /// 观察不足这个时长的基线不用于估算。
    static let minimumSeconds: TimeInterval = 20
    /// 太久没有更新的基线不再可信。
    static let staleAfter: TimeInterval = 14 * 86_400

    init(updatedAt: Date) { self.updatedAt = updatedAt }

    mutating func add(cpu: Double?, gpu: Double?, compositing: Double?, seconds: TimeInterval, at date: Date) {
        guard seconds > 0, seconds.isFinite else { return }
        if let cpu, cpu.isFinite, cpu >= 0 {
            let weight = min(cpuSeconds, Self.window)
            cpuPercent = (cpuPercent * weight + cpu * seconds) / (weight + seconds)
            cpuSeconds += seconds
        }
        if let gpu, gpu.isFinite, gpu >= 0 {
            let weight = min(gpuSeconds, Self.window)
            gpuPercent = (gpuPercent * weight + gpu * seconds) / (weight + seconds)
            gpuSeconds += seconds
            // 合成占比按同样的窗口衰减，偶发的一帧不会让应用长期被当作视频类。
            let share = compositing.map { max(0, $0) } ?? 0
            compositingPercent = (compositingPercent * weight + share * seconds) / (weight + seconds)
        }
        updatedAt = date
    }

    func isFresh(at date: Date) -> Bool { date.timeIntervalSince(updatedAt) < Self.staleAfter }
    func cpu(at date: Date) -> Double? { cpuSeconds >= Self.minimumSeconds && isFresh(at: date) ? cpuPercent : nil }
    func gpu(at date: Date) -> Double? { gpuSeconds >= Self.minimumSeconds && isFresh(at: date) ? gpuPercent : nil }
}

/// 一个应用一天内估算省下的资源。
struct SavingsAmount: Codable, Equatable, Sendable {
    /// 估算省下的 CPU 时间，单位为单核秒。
    var cpuSeconds: Double = 0
    /// 估算省下的 GPU 执行时间（含窗口合成），单位为秒，只在暂停期间计入。
    var gpuSeconds: Double = 0
    /// 性能限制生效的时长。
    var limitedSeconds: Double = 0

    static func + (left: SavingsAmount, right: SavingsAmount) -> SavingsAmount {
        SavingsAmount(cpuSeconds: left.cpuSeconds + right.cpuSeconds, gpuSeconds: left.gpuSeconds + right.gpuSeconds,
                      limitedSeconds: left.limitedSeconds + right.limitedSeconds)
    }
}

/// 一次读数覆盖的时间段里，应用所处的状态。
enum SavingsPhase: Equatable, Sendable {
    /// 在后台且没有受到性能限制：更新基线。
    case unlimitedBackground
    /// 性能限制或暂停生效：按基线与实际占用之差计入节省。
    case limited(suspended: Bool)
    /// 前台、只降低优先级等情况：不更新基线，也不计入节省。
    case other
}

struct SavingsEntry: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let amount: SavingsAmount
}

/// 按天累计每个应用估算省下的 CPU 与 GPU 时间，并保存各应用的后台基线。
///
/// 估算口径：节省 = max(0, 基线 CPU − 实际 CPU) × 时长；暂停期间进程不执行，GPU 节省按基线 GPU × 时长估算。
/// 基线为该应用最近在后台且未受限时的平均占用，不足 20 秒观察或超过 14 天未更新时不估算。
struct SavingsLedger: Codable, Equatable, Sendable {
    var version = 1
    /// 键为本地日期 yyyy-MM-dd，值为各应用当天的节省。
    var days: [String: [String: SavingsAmount]] = [:]
    var baselines: [String: UsageBaseline] = [:]
    /// 应用显示名称，应用退出后报告仍能显示。
    var names: [String: String] = [:]

    static let retentionDays = 30
    static let baselineLimit = 300

    /// 记录一次读数。`seconds` 为这次读数覆盖的时长，由调用方按相邻读数间隔计算并限制上限。
    /// 返回本次计入的节省。
    @discardableResult
    mutating func record(id: String, name: String, phase: SavingsPhase, cpuPercent: Double?, gpuPercent: Double?,
                         compositingPercent: Double? = nil, seconds: TimeInterval, at date: Date,
                         calendar: Calendar = .current) -> SavingsAmount {
        guard seconds > 0, seconds.isFinite else { return SavingsAmount() }
        switch phase {
        case .other:
            return SavingsAmount()
        case .unlimitedBackground:
            var baseline = baselines[id] ?? UsageBaseline(updatedAt: date)
            baseline.add(cpu: cpuPercent, gpu: gpuPercent, compositing: compositingPercent, seconds: seconds, at: date)
            baselines[id] = baseline
            names[id] = name
            return SavingsAmount()
        case .limited(let suspended):
            // 没有可信基线时只记录受限时长，不估算节省。
            var saved = SavingsAmount(limitedSeconds: seconds)
            let baseline = baselines[id]
            if let expected = baseline?.cpu(at: date), let actual = cpuPercent, actual.isFinite {
                saved.cpuSeconds = max(0, expected - max(0, actual)) / 100 * seconds
            }
            // CPU 上限下应用仍在运行，控制检查读不到 GPU，不估算 GPU；暂停时进程不提交 GPU 工作。
            if suspended, let expected = baseline?.gpu(at: date) {
                let actual = gpuPercent.map { max(0, $0) } ?? 0
                saved.gpuSeconds = max(0, expected - actual) / 100 * seconds
            }
            let key = Self.dayKey(date, calendar: calendar)
            let current = days[key]?[id] ?? SavingsAmount()
            days[key, default: [:]][id] = current + saved
            names[id] = name
            return saved
        }
    }

    /// 最近 `count` 天（含今天）的合计。
    func total(days count: Int, endingAt date: Date, calendar: Calendar = .current) -> SavingsAmount {
        entries(days: count, endingAt: date, calendar: calendar).reduce(SavingsAmount()) { $0 + $1.amount }
    }

    /// 最近 `count` 天按应用合计，按省下的 CPU 时间从高到低排列。
    func entries(days count: Int, endingAt date: Date, calendar: Calendar = .current) -> [SavingsEntry] {
        var totals: [String: SavingsAmount] = [:]
        for key in Self.dayKeys(count, endingAt: date, calendar: calendar) {
            for (id, amount) in days[key] ?? [:] { totals[id] = (totals[id] ?? SavingsAmount()) + amount }
        }
        return totals.map { SavingsEntry(id: $0.key, name: names[$0.key] ?? $0.key, amount: $0.value) }
            .sorted {
                if $0.amount.cpuSeconds != $1.amount.cpuSeconds { return $0.amount.cpuSeconds > $1.amount.cpuSeconds }
                if $0.amount.gpuSeconds != $1.amount.gpuSeconds { return $0.amount.gpuSeconds > $1.amount.gpuSeconds }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    /// 最近 `count` 天每天的合计，最早的一天在前，用于柱状图。
    func daily(_ count: Int, endingAt date: Date, calendar: Calendar = .current) -> [(day: Date, amount: SavingsAmount)] {
        let today = calendar.startOfDay(for: date)
        return (0..<count).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let amount = (days[Self.dayKey(day, calendar: calendar)] ?? [:]).values.reduce(SavingsAmount(), +)
            return (day, amount)
        }
    }

    /// 删除超过保留期的日期和长期未更新的基线，并限制基线数量。
    mutating func prune(now: Date, calendar: Calendar = .current) {
        let keep = Set(Self.dayKeys(Self.retentionDays, endingAt: now, calendar: calendar))
        days = days.filter { keep.contains($0.key) }
        baselines = baselines.filter { $0.value.isFresh(at: now) }
        if baselines.count > Self.baselineLimit {
            let recent = baselines.sorted { $0.value.updatedAt > $1.value.updatedAt }.prefix(Self.baselineLimit)
            baselines = Dictionary(uniqueKeysWithValues: recent.map { ($0.key, $0.value) })
        }
        let used = Set(days.values.flatMap(\.keys)).union(baselines.keys)
        names = names.filter { used.contains($0.key) }
    }

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func dayKeys(_ count: Int, endingAt date: Date, calendar: Calendar = .current) -> [String] {
        let today = calendar.startOfDay(for: date)
        return (0..<max(0, count)).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today).map { dayKey($0, calendar: calendar) }
        }
    }

    /// 按相邻读数计算本次覆盖的时长；间隔过长（睡眠、长时间未采样）时不计入，避免把空档算成节省。
    static let maximumGap: TimeInterval = 12
    static func coveredSeconds(since previous: Date?, now: Date) -> TimeInterval? {
        guard let previous else { return nil }
        let elapsed = now.timeIntervalSince(previous)
        return elapsed > 0 && elapsed <= maximumGap ? elapsed : nil
    }
}
