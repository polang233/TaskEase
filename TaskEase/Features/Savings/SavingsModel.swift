import Foundation
import Observation

/// 把已有采样的读数累计到节省记录，节流写盘。不新增采样或计时器：只在显示刷新和控制检查返回时调用。
@MainActor @Observable
final class SavingsModel {
    private(set) var ledger: SavingsLedger
    @ObservationIgnored private var store: SavingsStore?
    @ObservationIgnored private var lastObserved: [String: Date] = [:]
    @ObservationIgnored private var dirty = false
    @ObservationIgnored private var lastSaved = Date.distantPast
    /// 写盘的最短间隔；睡眠、退出时立即写入。
    static let saveInterval: TimeInterval = 60

    init(store: SavingsStore?, ledger: SavingsLedger? = nil) {
        self.store = store
        var loaded = ledger ?? store?.load() ?? SavingsLedger()
        loaded.prune(now: Date())
        self.ledger = loaded
    }

    /// 合并一次采样。`phase` 由调用方按读数覆盖期间的规则状态给出。
    func observe(_ apps: [AppReading], at date: Date = Date(), phase: (AppReading) -> SavingsPhase) {
        var changed = false
        for app in apps where app.isRunning {
            // 第一帧没有 CPU 读数，只建立时间基准。
            guard app.cpuPercent != nil else { lastObserved[app.id] = date; continue }
            let covered = SavingsLedger.coveredSeconds(since: lastObserved[app.id], now: date)
            lastObserved[app.id] = date
            guard let covered else { continue }
            let current = phase(app)
            guard current != .other else { continue }
            ledger.record(id: app.id, name: app.name, phase: current, cpuPercent: app.cpuPercent,
                          gpuPercent: app.totalGPUPercent, compositingPercent: app.compositingGPUPercent,
                          seconds: covered, at: date)
            changed = true
        }
        if changed { dirty = true }
        if dirty && date.timeIntervalSince(lastSaved) >= Self.saveInterval { flush(at: date) }
    }

    /// 睡眠或长时间停顿后重新建立时间基准，空档不计入。
    func resetTiming() { lastObserved.removeAll() }

    func flush(at date: Date = Date()) {
        guard dirty, let store else { return }
        ledger.prune(now: date)
        do {
            try store.save(ledger)
            dirty = false
            lastSaved = date
        } catch {
            // 写盘失败不影响规则执行，下次到期重试。
            lastSaved = date
        }
    }

    /// 清除数据前停止写盘，避免退出时把记录重新写回。
    func stopPersisting() { store = nil; dirty = false }

    func reset() {
        ledger = SavingsLedger()
        lastObserved.removeAll()
        dirty = true
        flush()
    }

    func baseline(for id: String) -> UsageBaseline? { ledger.baselines[id] }

    var today: SavingsAmount { ledger.total(days: 1, endingAt: Date()) }
    var week: SavingsAmount { ledger.total(days: 7, endingAt: Date()) }
    func entries(days: Int) -> [SavingsEntry] { ledger.entries(days: days, endingAt: Date()) }

    /// 预览用的示例记录：数值为虚构，只用于界面布局。
    static func fixture(now: Date = Date()) -> SavingsLedger {
        var ledger = SavingsLedger()
        let calendar = Calendar.current
        let samples: [(String, String, Double, Double)] = [
            ("example.browser", String(localized: "preview.app.browser"), 0.32, 0.08),
            ("example.editor", String(localized: "preview.app.editor"), 0.06, 0)
        ]
        for (id, name, cpu, gpu) in samples {
            ledger.names[id] = name
            var baseline = UsageBaseline(updatedAt: now)
            baseline.add(cpu: cpu * 100, gpu: gpu * 100, compositing: gpu * 60, seconds: 600, at: now)
            ledger.baselines[id] = baseline
            for offset in 0..<7 {
                guard let day = calendar.date(byAdding: .day, value: -offset, to: now) else { continue }
                let hours = Double(2 + (offset * 3) % 5)
                ledger.days[SavingsLedger.dayKey(day), default: [:]][id] =
                    SavingsAmount(cpuSeconds: cpu * hours * 2_400, gpuSeconds: gpu * hours * 3_000, limitedSeconds: hours * 3_600)
            }
        }
        return ledger
    }
}
