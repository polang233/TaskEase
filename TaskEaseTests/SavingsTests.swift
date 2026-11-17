import Foundation
import Testing
@testable import TaskEase

struct SavingsTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    /// 先在后台未受限时观察 60 秒建立基线，再按受限读数累计节省。
    @Test func savingsUseBackgroundBaselineMinusMeasuredUsage() {
        var ledger = SavingsLedger()
        for step in 0..<30 {
            ledger.record(id: "app", name: "App", phase: .unlimitedBackground, cpuPercent: 40, gpuPercent: 10,
                          seconds: 2, at: start.addingTimeInterval(Double(step) * 2), calendar: calendar)
        }
        #expect(ledger.baselines["app"]?.cpu(at: start) == 40)
        // CPU 上限 20%：每 2 秒省 (40 − 20)% × 2 秒 = 0.4 秒；不估算 GPU。
        let limited = ledger.record(id: "app", name: "App", phase: .limited(suspended: false), cpuPercent: 20, gpuPercent: nil,
                                    seconds: 2, at: start.addingTimeInterval(62), calendar: calendar)
        #expect(abs(limited.cpuSeconds - 0.4) < 1e-9)
        #expect(limited.gpuSeconds == 0)
        // 暂停：CPU 全部节省，GPU 按基线计入。
        let paused = ledger.record(id: "app", name: "App", phase: .limited(suspended: true), cpuPercent: 0, gpuPercent: nil,
                                   seconds: 10, at: start.addingTimeInterval(72), calendar: calendar)
        #expect(abs(paused.cpuSeconds - 4) < 1e-9)
        #expect(abs(paused.gpuSeconds - 1) < 1e-9)
        let today = ledger.total(days: 1, endingAt: start.addingTimeInterval(80), calendar: calendar)
        #expect(abs(today.cpuSeconds - 4.4) < 1e-9)
        #expect(today.limitedSeconds == 12)
        #expect(ledger.entries(days: 7, endingAt: start, calendar: calendar).first?.name == "App")
    }

    @Test func noEstimateWithoutEnoughBaselineOrWhenUsageRises() {
        var ledger = SavingsLedger()
        // 没有基线：只记受限时长。
        var saved = ledger.record(id: "app", name: "App", phase: .limited(suspended: true), cpuPercent: 0, gpuPercent: 0,
                                  seconds: 5, at: start, calendar: calendar)
        #expect(saved.cpuSeconds == 0 && saved.limitedSeconds == 5)
        // 观察不足 20 秒的基线不使用。
        ledger.record(id: "app", name: "App", phase: .unlimitedBackground, cpuPercent: 50, gpuPercent: nil,
                      seconds: 10, at: start, calendar: calendar)
        saved = ledger.record(id: "app", name: "App", phase: .limited(suspended: false), cpuPercent: 5, gpuPercent: nil,
                              seconds: 5, at: start, calendar: calendar)
        #expect(saved.cpuSeconds == 0)
        ledger.record(id: "app", name: "App", phase: .unlimitedBackground, cpuPercent: 50, gpuPercent: nil,
                      seconds: 10, at: start, calendar: calendar)
        // 实测高于基线时不记为负数。
        saved = ledger.record(id: "app", name: "App", phase: .limited(suspended: false), cpuPercent: 80, gpuPercent: nil,
                              seconds: 5, at: start, calendar: calendar)
        #expect(saved.cpuSeconds == 0)
        // 前台、只降优先级等情况不更新基线也不计入。
        ledger.record(id: "app", name: "App", phase: .other, cpuPercent: 300, gpuPercent: nil, seconds: 100, at: start, calendar: calendar)
        #expect(ledger.baselines["app"]?.cpuPercent == 50)
        // 基线超过 14 天未更新即失效。
        saved = ledger.record(id: "app", name: "App", phase: .limited(suspended: false), cpuPercent: 0, gpuPercent: nil,
                              seconds: 5, at: start.addingTimeInterval(15 * 86_400), calendar: calendar)
        #expect(saved.cpuSeconds == 0)
    }

    @Test func baselineFollowsRecentBackgroundUsage() {
        var baseline = UsageBaseline(updatedAt: start)
        baseline.add(cpu: 100, gpu: nil, compositing: nil, seconds: 600, at: start)
        // 窗口约 10 分钟：再观察 10 分钟 0% 后基线回落到一半。
        baseline.add(cpu: 0, gpu: nil, compositing: nil, seconds: 600, at: start)
        #expect(abs(baseline.cpuPercent - 50) < 1e-9)
        #expect(baseline.gpu(at: start) == nil)
    }

    @Test func dailyTotalsSplitByLocalDayAndPruneOldDays() {
        var ledger = SavingsLedger()
        ledger.record(id: "app", name: "App", phase: .unlimitedBackground, cpuPercent: 100, gpuPercent: nil,
                      seconds: 60, at: start, calendar: calendar)
        for offset in 0..<40 {
            ledger.record(id: "app", name: "App", phase: .limited(suspended: true), cpuPercent: 0, gpuPercent: nil,
                          seconds: 10, at: start.addingTimeInterval(-Double(offset) * 86_400 + 1), calendar: calendar)
            // 基线随时间保持新鲜。
            ledger.baselines["app"]?.updatedAt = start
        }
        #expect(abs(ledger.total(days: 7, endingAt: start, calendar: calendar).cpuSeconds - 70) < 1e-9)
        #expect(ledger.daily(7, endingAt: start, calendar: calendar).count == 7)
        ledger.prune(now: start, calendar: calendar)
        #expect(ledger.days.count == SavingsLedger.retentionDays)
        #expect(ledger.names["app"] == "App")
    }

    @Test func gapsLongerThanASamplingIntervalAreNotCounted() {
        #expect(SavingsLedger.coveredSeconds(since: nil, now: start) == nil)
        #expect(SavingsLedger.coveredSeconds(since: start, now: start.addingTimeInterval(2)) == 2)
        #expect(SavingsLedger.coveredSeconds(since: start, now: start.addingTimeInterval(600)) == nil)
        #expect(SavingsLedger.coveredSeconds(since: start, now: start.addingTimeInterval(-1)) == nil)
    }

    @Test func ruleStatusesMapToSavingsPhases() {
        #expect(AppModel.savingsPhase(status: .budget, background: true) == .limited(suspended: false))
        #expect(AppModel.savingsPhase(status: .suspended, background: true) == .limited(suspended: true))
        #expect(AppModel.savingsPhase(status: .waiting, background: true) == .unlimitedBackground)
        #expect(AppModel.savingsPhase(status: .unmanaged, background: true) == .unlimitedBackground)
        #expect(AppModel.savingsPhase(status: .unmanaged, background: false) == .other)
        #expect(AppModel.savingsPhase(status: .gentle, background: true) == .other)
        #expect(AppModel.savingsPhase(status: .foreground, background: false) == .other)
        #expect(AppModel.savingsPhase(status: nil, background: true) == .other)
    }

    @Test func storeRoundTripsAndKeepsBackupOfCorruptFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TaskEase.Savings." + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SavingsStore(url: root.appendingPathComponent("savings.v1.json"))
        #expect(store.load() == SavingsLedger())
        var ledger = SavingsLedger()
        ledger.record(id: "app", name: "App", phase: .unlimitedBackground, cpuPercent: 30, gpuPercent: 4,
                      seconds: 30, at: Date(timeIntervalSince1970: 1_800_000_000))
        try store.save(ledger)
        #expect(store.load() == ledger)
        try Data("broken".utf8).write(to: store.url)
        #expect(store.load() == SavingsLedger())
        #expect(FileManager.default.fileExists(atPath: store.url.appendingPathExtension("invalid-backup").path))
    }

    @MainActor @Test func modelCountsOnlyCoveredIntervalsAndStopsWritingAfterErase() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TaskEase.Savings." + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SavingsStore(url: root.appendingPathComponent("savings.v1.json"))
        let model = SavingsModel(store: store)
        var app = AppReading(id: "app", name: "App", bundlePaths: [], primaryPIDs: [], targets: [], samples: [],
                             cpuPercent: 50, memoryBytes: 0, readRate: 0, writeRate: 0, canControl: true, isHidden: false)
        let now = Date()
        for step in 0...15 {
            model.observe([app], at: now.addingTimeInterval(Double(step) * 2)) { _ in .unlimitedBackground }
        }
        #expect(model.baseline(for: "app")?.cpuSeconds == 30)
        app.cpuPercent = 0
        model.observe([app], at: now.addingTimeInterval(32)) { _ in .limited(suspended: true) }
        // 睡眠后的第一帧只重建时间基准。
        model.resetTiming()
        model.observe([app], at: now.addingTimeInterval(500)) { _ in .limited(suspended: true) }
        #expect(abs(model.today.cpuSeconds - 1) < 1e-9 || Calendar.current.isDateInToday(now) == false)
        model.flush()
        #expect(FileManager.default.fileExists(atPath: store.url.path))
        try FileManager.default.removeItem(at: root)
        model.stopPersisting()
        model.observe([app], at: now.addingTimeInterval(502)) { _ in .limited(suspended: true) }
        model.flush()
        #expect(!FileManager.default.fileExists(atPath: store.url.path))
    }
}
