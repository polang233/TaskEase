import AppKit
import Foundation
import Network
import Observation

/// 拥有统计同意状态、低频调度与发送任务；关闭时取消全部活动。
@MainActor @Observable
final class UsageAnalytics {
    private(set) var enabled = false
    private(set) var lastSuccess: Date?
    private(set) var message = "未开启"
    var isConfigured: Bool { sender != nil }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let sender: (any UsageSending)?
    @ObservationIgnored private let fixtures: Bool
    @ObservationIgnored private let clock: @MainActor () -> Date
    @ObservationIgnored private let observesSystem: Bool
    @ObservationIgnored private var context: @MainActor () -> UsageContext? = { nil }
    @ObservationIgnored private var state = DailyUsageState()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var pathMonitor: NWPathMonitor?
    @ObservationIgnored private var observers: AnalyticsClockEvents?
    @ObservationIgnored private var suspended = false
    @ObservationIgnored private var running = false
    @ObservationIgnored private var generation = 0
    private static let enabledKey = "usageAnalytics.enabled"
    private static let stateKey = "usageAnalytics.v1"

    init(fixtures: Bool = false, defaults: UserDefaults = .standard, sender: (any UsageSending)? = nil,
         observesSystem: Bool = true, deferStart: Bool = false, clock: @escaping @MainActor () -> Date = { Date() }) {
        #if DEBUG
        self.fixtures = fixtures || sender == nil
        #else
        self.fixtures = fixtures
        #endif
        self.defaults = defaults
        self.clock = clock
        self.observesSystem = observesSystem
        self.sender = sender ?? PostHogConfiguration.load().map { PostHogClient(configuration: $0) }
        // 夹具与开发构建不读取生产同意状态，也不自动发送。
        guard !self.fixtures else { return }
        if let data = defaults.data(forKey: Self.stateKey), let stored = try? JSONDecoder().decode(DailyUsageState.self, from: data) {
            state = stored
            lastSuccess = stored.lastSuccess
        }
        enabled = defaults.bool(forKey: Self.enabledKey)
        if enabled && !deferStart { start() }
    }

    /// 用户主动开启后才创建随机安装标识；关闭不影响应用规则和资源监控。
    func setEnabled(_ value: Bool) {
        guard value != enabled else { return }
        enabled = value
        if fixtures { message = value ? "启动及运行期间低频发送" : "未开启"; return }
        defaults.set(value, forKey: Self.enabledKey)
        if value { start() }
        else { stop(); message = "未开启" }
    }

    /// 等规则与偏好读取完成，再采集功能概况并恢复已同意的统计。
    func activate(context: @escaping @MainActor () -> UsageContext?) {
        self.context = context
        if enabled && !running && !fixtures { start() }
    }

    private func start() {
        guard sender != nil else { message = "统计服务尚未配置"; return }
        running = true
        suspended = false
        if state.installationID == nil { state.installationID = UUID(); persist() }
        if observesSystem {
            observers = AnalyticsClockEvents { [weak self] in self?.reconcile() }
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { [weak self] path in
                if path.status == .satisfied { Task { @MainActor in self?.reconcile() } }
            }
            monitor.start(queue: DispatchQueue(label: "TaskEase.Analytics.Network", qos: .utility))
            pathMonitor = monitor
        }
        reconcile()
    }

    /// 事件驱动检查，关闭时不安排定时器。每个事件最多尝试三次，间隔五分钟。
    func reconcile() {
        timer?.invalidate(); timer = nil
        guard enabled, running, !fixtures, !suspended, task == nil, let sender else { return }
        let now = clock()
        let calendar = DailyUsageSchedule.calendar()
        switch DailyUsageSchedule.action(now: now, state: state, calendar: calendar) {
        case .wait(let next):
            message = "等待下次上报"
            schedule(next, now: now)
        case .send:
            guard let installationID = state.installationID else { return }
            let day = DailyUsageSchedule.day(now, calendar: calendar)
            if state.pending?.localDay != day || state.attempts >= 3 {
                state.pending = DailyUsageEvent.capture(installationID: installationID, now: now, calendar: calendar, usage: context())
                state.attempts = 0
            }
            guard let event = state.pending else { return }
            state.attempts += 1
            state.retryAfter = now.addingTimeInterval(DailyUsageSchedule.retryInterval)
            persist()
            message = "正在发送"
            let requestGeneration = generation
            task = Task { [weak self] in
                do {
                    try await sender.send(event)
                    guard !Task.isCancelled, let self, self.generation == requestGeneration, self.enabled else { return }
                    self.state.lastSuccess = event.timestamp
                    self.state.pending = nil
                    self.state.attempts = 0
                    self.state.retryAfter = nil
                    self.lastSuccess = event.timestamp
                    self.persist()
                    self.task = nil
                    self.reconcile()
                } catch {
                    guard !Task.isCancelled, let self, self.generation == requestGeneration, self.enabled else { return }
                    self.task = nil
                    self.reconcile()
                    self.message = "发送未完成，稍后重试"
                }
            }
        }
    }

    private func schedule(_ date: Date, now: Date) {
        let next = Timer(timeInterval: max(1, date.timeIntervalSince(now)), repeats: false) { [weak self] _ in
            Task { @MainActor in self?.reconcile() }
        }
        next.tolerance = 60
        RunLoop.main.add(next, forMode: .common)
        timer = next
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: Self.stateKey) }
    }

    func prepareForSleep() { suspended = true; cancelRequest() }
    func wake() { suspended = false; reconcile() }

    private func cancelRequest() {
        generation += 1
        timer?.invalidate(); timer = nil
        task?.cancel(); task = nil
    }

    /// 清理应用数据前调用，使取消后的发送回调不会重新写入偏好域。
    func stop() {
        running = false
        cancelRequest()
        pathMonitor?.cancel(); pathMonitor = nil
        observers = nil
    }

    var hasScheduledTimer: Bool { timer != nil }
}

/// 时钟、时区和跨日变化重新计算下次上报期限；此对象负责释放观察令牌。
private final class AnalyticsClockEvents {
    private var tokens: [NSObjectProtocol] = []
    @MainActor init(action: @escaping @MainActor @Sendable () -> Void) {
        for name in [NSNotification.Name.NSCalendarDayChanged, .NSSystemTimeZoneDidChange, .NSSystemClockDidChange] {
            tokens.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in action() }
            })
        }
    }
    deinit { for token in tokens { NotificationCenter.default.removeObserver(token) } }
}
