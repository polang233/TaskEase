import AppKit
import Foundation
import Observation

/// 集中维护规则、界面与前后台状态，协调异步采样和控制进程。
@MainActor @Observable
final class AppModel {
    private(set) var apps: [AppReading] = []
    private(set) var system = SystemReading()
    private(set) var networkMonitorStatus: NetworkMonitorStatus = .disabled
    private(set) var rules: [String: AppRule] = [:]
    private(set) var networkRules: [String: NetworkRule] = [:]
    private(set) var networkRuleError: String?
    private(set) var preferences = AppPreferences()
    private(set) var language = AppLanguage.saved
    private(set) var enabled = false
    private(set) var applicationList: ApplicationList = .running
    var search = ""
    var selectedID: String?
    var errorMessage: String?
    /// 后台音量调整失败（多为未授予系统录音权限）的应用。
    private(set) var volumeFailures: Set<String> = []
    private(set) var sampledAt = Date()
    /// 详情折线图用的近期显示采样。
    private(set) var usageHistory = UsageHistory()
    private(set) var isRefreshing = false
    private(set) var managementIsOpen = false
    private(set) var managementDisplayPaused = false
    private(set) var statisticsIsOpen = false
    private(set) var foregroundID: String?
    /// 临时暂停与“立即恢复”，按应用标识保存在内存中。
    private(set) var temporaryActions: [String: TemporaryAction] = [:]
    let preview: Bool
    let usageAnalytics: UsageAnalytics
    let usageStatistics: UsageStatisticsModel
    let updates: UpdateChecker
    /// 节省报告：借已有采样累计估算省下的 CPU 与 GPU 时间。
    let savings: SavingsModel
    /// 智能建议的阈值与忽略记录；建议本身由节省记录中的后台基线算出。
    let suggestionCenter: SuggestionsModel

    @ObservationIgnored private var savedApplications: [String: SavedApplication] = [:]
    @ObservationIgnored private var reportMetadata: [String: SavedApplication] = [:]
    @ObservationIgnored private var backgroundSince: [String: UInt64] = [:]
    @ObservationIgnored private var primaryIdentities: [String: Set<ProcessIdentity>] = [:]
    @ObservationIgnored private var lastDisplaySample: UInt64?
    @ObservationIgnored private let monitor = ProcessMonitor()
    @ObservationIgnored private let controller = WorkerController()
    @ObservationIgnored private let volume = AppVolume()
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var timer: Timer?
    /// 最近几次工作进程意外退出的时间，用于限制自动重启次数。
    @ObservationIgnored private var workerExits: [UInt64] = []
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var pendingRefresh: Bool?
    @ObservationIgnored private var events: WorkspaceEvents?
    @ObservationIgnored private var managementWindow: ManagementWindowController?
    @ObservationIgnored private var utilityWindows: [UtilityWindowKind: UtilityWindowController] = [:]
    @ObservationIgnored private var openUtilities: Set<UtilityWindowKind> = []
    @ObservationIgnored private weak var menuWindow: NSWindow?
    @ObservationIgnored private var sleeping = false
    @ObservationIgnored private var isShutdown = false

    init(preview: Bool = false) {
        self.preview = preview
        usageAnalytics = UsageAnalytics(fixtures: preview, deferStart: true)
        usageStatistics = UsageStatisticsModel(fixtures: preview)
        updates = UpdateChecker(fixtures: preview)
        savings = preview ? SavingsModel(store: nil, ledger: SavingsModel.fixture()) : SavingsModel(store: .current)
        suggestionCenter = SuggestionsModel(defaults: preview ? nil : .standard)
        if preview {
            apps = Self.exampleApps
            usageHistory.seedFixture(from: apps, now: Date())
            system = SystemReading(cpuPercent: 18, gpuPercent: 24, thermal: .nominal,
                memory: .init(usedBytes: 14 * 1_073_741_824, totalBytes: 24 * 1_073_741_824, compressedBytes: 1_073_741_824, swapBytes: 512 * 1_048_576),
                network: .init(receiveRate: 12_345_678, sendRate: 123_456), temperatureCelsius: 54.3,
                gpuSources: [GPUSource(name: String(localized: "preview.app.browser"), percent: 15.3, compositing: 12.6), GPUSource(name: "WindowServer", percent: 4.2)])
            foregroundID = "example.editor"
            selectedID = apps.first?.id
            return
        }
        _ = Recovery.restore()
        loadStoredState()
        applyAppearance()
        // 每次启动先清理上次更新中途退出的残留，再稍后检查一次更新，避开首轮采样；发现新版本只显示提示，不弹窗。
        Task.detached(priority: .utility) { UpdateInstaller.removeLeftovers() }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            self?.updates.check(automatic: true)
        }
        usageAnalytics.activate { [weak self] in
            guard let self else { return nil }
            return UsageContext(cpuRuleCount: self.configuredCount,
                networkRuleCount: self.networkRules.values.filter(\.isActive).count,
                managementEnabled: self.enabled, theme: self.preferences.theme.rawValue,
                refreshSeconds: self.preferences.refreshInterval.rawValue,
                networkDisplayEnabled: self.preferences.networkActivityVisible,
                foregroundRefreshOnly: self.preferences.refreshOnlyInForeground)
        }
        controller.onError = { [weak self] message in
            guard let self else { return }
            self.errorMessage = message
            self.enabled = false
            self.defaults.set(false, forKey: "managementEnabled")
            // 总开关关闭时临时操作一并结束，避免 reconcile 重启出错的工作进程。
            self.temporaryActions.removeAll()
            self.controller.stop()
            self.reconcile()
        }
        volume.onChange = { [weak self] in
            guard let self else { return }
            self.volumeFailures = self.volume.failedIDs
        }
        controller.onUnexpectedExit = { [weak self] in
            // 限制已由恢复记录撤销；10 分钟内最多自动重启 3 次，反复退出再关闭总开关并提示。
            guard let self, self.enabled, !self.sleeping, !self.isShutdown else { return false }
            self.workerExits = self.workerExits.filter { NativeProcess.seconds(since: $0) < 600 }
            guard self.workerExits.count < 3 else { return false }
            self.workerExits.append(NativeProcess.now)
            self.reconcile()
            return true
        }
        events = WorkspaceEvents(
            onFocus: { [weak self] in self?.focusChanged() },
            onMembership: { [weak self] id in self?.membershipChanged(id) },
            onSleep: { [weak self] in self?.prepareForSleep() },
            onWake: { [weak self] in self?.wake() },
            onVisibility: { [weak self] in self?.displayVisibilityChanged() }
        )
        foregroundID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if enabled && configuredCount > 0 { refresh(force: true) }
    }

    var configuredCount: Int { rules.values.filter(\.isActive).count }
    var managedCount: Int { apps.filter { Policy.shouldControl($0.status) }.count }
    var helperPID: Int32? { controller.helperPID }
    /// 有有效规则或正在进行的临时暂停时才能打开总开关。
    var canEnable: Bool { (configuredCount > 0 || temporaryActions.values.contains(where: \.isPause)) && !isShutdown }
    var hasScheduledRefresh: Bool { timer != nil }

    private var visibleRuleIDs: Set<String> {
        Set(rules.keys).union(preferences.networkFeaturesEnabled ? Set(networkRules.keys) : [])
    }
    var savedRuleCount: Int { visibleRuleIDs.count }

    var configuredApps: [AppReading] {
        visibleRuleIDs.map { id in
            apps.first { $0.id == id } ?? .offline(id: id, metadata: savedApplications[id])
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var visibleRunningApps: [AppReading] {
        apps.filter { preferences.showSystemApps || !$0.isSystemApp }
    }

    var filteredApps: [AppReading] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = applicationList == .running ? visibleRunningApps : configuredApps
        return Self.sorted(source.filter {
            AppSearch.matches(query, name: $0.name, aliases: $0.aliases, id: $0.id)
        }, by: effectiveSortKey)
    }

    /// 网络排序依赖应用网络速度显示；关闭后退回 CPU。
    var effectiveSortKey: AppSortKey {
        preferences.sortKey == .network && !preferences.networkActivityVisible ? .cpu : preferences.sortKey
    }

    var sortKeys: [AppSortKey] {
        AppSortKey.allCases.filter { $0 != .network || preferences.networkActivityVisible }
    }

    /// 数值降序，缺失值排在最后，相同时按名称排列，避免刷新时行顺序跳动。
    static func sorted(_ apps: [AppReading], by key: AppSortKey) -> [AppReading] {
        func value(_ app: AppReading) -> Double? {
            guard app.isRunning else { return nil }
            switch key {
            case .cpu: return app.cpuPercent
            case .memory: return Double(app.memoryBytes)
            case .gpu: return app.totalGPUPercent
            case .disk: return app.readRate + app.writeRate
            case .network: return app.network.map { ($0.receiveRate ?? 0) + ($0.sendRate ?? 0) }
            case .name: return nil
            }
        }
        return apps.sorted { left, right in
            if key != .name {
                let a = value(left) ?? -1, b = value(right) ?? -1
                if a != b { return a > b }
            }
            return left.name.localizedStandardCompare(right.name) == .orderedAscending
        }
    }

    var selectedApp: AppReading? { filteredApps.first { $0.id == selectedID } }

    /// 还没有规则、在后台平均占用超过阈值的运行中应用。系统应用和不可控制的应用不列出。
    var suggestions: [Suggestion] {
        guard !isShutdown else { return [] }
        let candidates = apps.filter { $0.isRunning && $0.canControl && !$0.isSystemApp && !$0.id.hasPrefix("com.apple.") }
            .map { SuggestionEngine.Candidate(id: $0.id, name: $0.name, category: suggestionCenter.category(for: $0)) }
        return SuggestionEngine.suggestions(baselines: savings.ledger.baselines, candidates: candidates,
                                            excluded: Set(rules.keys).union(networkRules.keys),
                                            settings: suggestionCenter.settings, now: Date())
    }

    /// 一键套用建议。之前没有任何有效规则时同时打开总开关，让规则立即可用；用户主动关掉的总开关保持关闭。
    func applySuggestion(_ suggestion: Suggestion) {
        let hadActiveRules = configuredCount > 0
        setRule(suggestion.id, rule: suggestion.method.rule)
        guard rules[suggestion.id]?.isActive == true else { return }
        if !hadActiveRules && !enabled { setEnabled(true) }
        if filteredApps.contains(where: { $0.id == suggestion.id }) { selectedID = suggestion.id }
    }

    /// 临时操作只作用于当前用户正在运行、可以设置规则的应用。
    func canAct(on id: String) -> Bool {
        guard !isShutdown, !id.isEmpty, id != Bundle.main.bundleIdentifier, !id.hasPrefix("com.apple.") else { return false }
        if let app = apps.first(where: { $0.id == id }) { return app.isRunning && app.canControl && !app.isSystemApp }
        if preview { return false }
        // 面板未打开、也没有规则时应用列表可能为空，直接向系统确认应用正在运行。
        return !RunningApplication.capture(showSystemApps: false, only: [id]).isEmpty
    }

    /// 临时暂停：应用在后台时暂停，直到期限；切回前台照常使用。不需要规则；总开关关闭时一并打开，
    /// 因为这是用户主动发起的限制。
    @discardableResult
    func pauseTemporarily(_ id: String, minutes: Double = TemporaryAction.defaultMinutes) -> Bool {
        guard canAct(on: id) else { return false }
        temporaryActions[id] = .pause(until: Date().addingTimeInterval(TemporaryAction.clampedMinutes(minutes) * 60))
        // 面板关闭时前台记录可能过期，先更新，避免暂停正在使用的应用。
        updateFocus()
        if !enabled {
            setEnabled(true)
        } else {
            reconcile()
            refresh(force: true)
        }
        return true
    }

    /// 立即恢复：取消临时暂停；规则正在限制时，让规则暂停执行一小时或直到下次切回该应用。
    @discardableResult
    func resumeNow(_ id: String) -> Bool {
        let wasPaused = temporaryActions[id]?.isPause == true
        let limited = apps.first { $0.id == id }.map { Policy.shouldControl($0.status) && $0.status != .held } == true
        guard wasPaused || limited || temporaryActions[id] != nil else { return false }
        if limited || (wasPaused && rules[id]?.isActive == true && enabled) {
            temporaryActions[id] = .release(until: Date().addingTimeInterval(TemporaryAction.releaseMinutes * 60))
        } else {
            temporaryActions[id] = nil
        }
        reconcile()
        refresh(force: true)
        return true
    }

    /// 结束临时操作，回到按规则执行。
    func clearTemporaryAction(_ id: String) {
        guard temporaryActions[id] != nil else { return }
        temporaryActions[id] = nil
        reconcile()
        refresh(force: true)
    }

    /// 执行 URL Scheme 或快捷指令的命令。
    func perform(_ command: AutomationCommand) -> AutomationOutcome {
        switch command {
        case .setLimits(let value):
            let target = value ?? !enabled
            guard !target || canEnable else {
                return AutomationOutcome(succeeded: false, message: String(localized: "automation.error.noRules"))
            }
            setEnabled(target)
            return AutomationOutcome(succeeded: true, message: target ? String(localized: "automation.limits.on")
                                                                      : String(localized: "automation.limits.off"))
        case .pause(let id, let minutes):
            let name = automationName(id)
            guard pauseTemporarily(id, minutes: minutes) else {
                return AutomationOutcome(succeeded: false, message: String(localized: "automation.error.app \(name)"))
            }
            return AutomationOutcome(succeeded: true,
                                     message: String(localized: "automation.paused \(name) \(Int(TemporaryAction.clampedMinutes(minutes)))"))
        case .resume(let id):
            let name = automationName(id)
            guard resumeNow(id) else {
                return AutomationOutcome(succeeded: false, message: String(localized: "automation.error.notLimited \(name)"))
            }
            return AutomationOutcome(succeeded: true, message: String(localized: "automation.resumed \(name)"))
        }
    }

    private func automationName(_ id: String) -> String {
        apps.first { $0.id == id }?.name ?? savedApplications[id]?.name ??
            NSRunningApplication.runningApplications(withBundleIdentifier: id).first?.localizedName ?? id
    }

    /// 导出 CPU 规则，格式与 rules.v1 相同。
    func exportRules() throws -> Data { try RuleTemplate.export(rules) }

    /// 导入规则模板：同一应用的规则被替换，其余保留；系统应用和本应用跳过。不改变总开关。
    @discardableResult
    func importRules(_ data: Data) throws -> RuleTemplate.Parsed {
        let parsed = try RuleTemplate.parse(data)
        var accepted: [String: AppRule] = [:]
        var skipped = parsed.skipped
        for (id, rule) in parsed.rules {
            if let app = apps.first(where: { $0.id == id }), app.isSystemApp { skipped.append(id); continue }
            accepted[id] = rule
        }
        guard !accepted.isEmpty, !isShutdown else { throw RuleTemplate.Failure.empty }
        for (id, rule) in accepted {
            if rule.isActive && rules[id]?.isActive != true { backgroundSince[id] = nil }
            rules[id] = rule
            if savedApplications[id] == nil {
                savedApplications[id] = apps.first { $0.id == id }.map(SavedApplication.init) ?? Self.installedMetadata(id)
            }
        }
        if accepted.values.contains(where: \.adjustsVolume) { volume.retry() }
        persistRules()
        normalizeEnablement()
        ensureSelection()
        reconcile()
        refresh(force: true)
        return RuleTemplate.Parsed(rules: accepted, skipped: skipped.sorted())
    }

    /// 从系统登记的应用包读取名称与路径，用于展示未运行的已配置应用。
    private static func installedMetadata(_ id: String) -> SavedApplication? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        let name = Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ??
            url.deletingPathExtension().lastPathComponent
        return SavedApplication(name: name, bundlePaths: [url.resolvingSymlinksInPath().path])
    }

    /// 报告与建议中显示的应用：优先用运行中的读数，其次用已保存的元数据或系统登记的应用包路径。
    func reportApplication(id: String, name: String) -> AppReading {
        if let app = apps.first(where: { $0.id == id }) { return app }
        if let metadata = savedApplications[id] ?? reportMetadata[id] { return .offline(id: id, metadata: metadata) }
        let paths = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id).map { [$0.resolvingSymlinksInPath().path] } ?? []
        let metadata = SavedApplication(name: name, bundlePaths: paths)
        reportMetadata[id] = metadata
        return .offline(id: id, metadata: metadata)
    }

    func allowsRuleEditing(_ app: AppReading) -> Bool {
        !isShutdown && !app.isSystemApp && !app.id.hasPrefix("com.apple.") && (app.canControl || rules[app.id] != nil || networkRules[app.id] != nil)
    }

    func setApplicationList(_ list: ApplicationList) {
        applicationList = list
        search = ""
        ensureSelection()
        if list == .running { refresh(force: true) }
    }

    func ensureSelection() {
        if !filteredApps.contains(where: { $0.id == selectedID }) { selectedID = filteredApps.first?.id }
    }

    func setEnabled(_ value: Bool) {
        guard !value || canEnable else { return }
        enabled = value
        errorMessage = nil
        // 总开关就是完全关闭：临时暂停和“立即恢复”一并结束。
        if !value { temporaryActions.removeAll() }
        // 总开关开启时重新计时，给已经位于后台的应用完整等待期。
        if value { backgroundSince.removeAll(); volume.retry() }
        if !preview { defaults.set(value, forKey: "managementEnabled") }
        reconcile()
        refresh(force: true)
    }

    func setRule(_ id: String, rule: AppRule) {
        let application = apps.first { $0.id == id } ?? configuredApps.first { $0.id == id }
        guard let application, allowsRuleEditing(application) else { return }
        let validated = rule.validated()
        let previous = rules[id]
        if previous?.isActive != true && validated.isActive { backgroundSince[id] = nil }
        if validated.adjustsVolume && previous?.adjustsVolume != true { volume.retry() }
        rules[id] = validated
        savedApplications[id] = SavedApplication(application)
        persistRules()
        normalizeEnablement()
        reconcile()
        // 拖动滑杆只改上限、音量或等待时间，成员不变，直接按缓存下发即可；
        // 只有开关某项限制时才需要重新扫描成员，避免拖动时连续触发完整扫描。
        if previous.map({ $0.isActive != validated.isActive || $0.needsWorker != validated.needsWorker
            || $0.adjustsVolume != validated.adjustsVolume }) ?? true {
            refresh(force: true)
        }
    }

    func resetRule(_ id: String) {
        guard rules[id] != nil || networkRules[id] != nil else { return }
        rules[id] = nil
        networkRules[id] = nil
        persistNetworkRules()
        savedApplications.removeValue(forKey: id)
        backgroundSince[id] = nil
        persistRules()
        normalizeEnablement()
        ensureSelection()
        reconcile()
        refresh(force: true)
    }

    /// 网络规则独立保存。当前构建只准备配置，系统扩展就绪前不执行控制。
    func setNetworkRule(_ id: String, rule: NetworkRule) {
        let application = apps.first { $0.id == id } ?? configuredApps.first { $0.id == id }
        guard let application, allowsRuleEditing(application) else { return }
        networkRules[id] = rule.validated()
        savedApplications[id] = SavedApplication(application)
        persistNetworkRules()
        persistRules()
        ensureSelection()
    }

    func removeNetworkRule(_ id: String) {
        networkRules[id] = nil
        if rules[id] == nil { savedApplications[id] = nil }
        persistNetworkRules()
        persistRules()
        ensureSelection()
    }

    func networkStatus(for id: String) -> NetworkRuleStatus {
        NetworkPolicy.status(rule: networkRules[id] ?? NetworkRule(), enabled: false,
                             controlAvailable: false, foreground: foregroundID == id, backgroundSeconds: 0)
    }

    private func persistNetworkRules() {
        guard !preview else { return }
        do {
            let data = try JSONEncoder().encode(networkRules)
            defaults.set(data, forKey: "networkRules.v1")
            networkRuleError = nil
        } catch { networkRuleError = String(localized: "error.networkRules.save \(error.localizedDescription)") }
    }

    func updatePreferences(_ update: (inout AppPreferences) -> Void) {
        var changed = preferences
        update(&changed)
        guard changed != preferences else { return }
        let themeChanged = changed.theme != preferences.theme
        preferences = changed
        if themeChanged { applyAppearance() }
        if !preview, let data = try? JSONEncoder().encode(changed) {
            defaults.set(data, forKey: "preferences.v1")
        }
        ensureSelection()
        scheduleRefresh()
        refresh(force: true)
    }

    func applyAppearance() {
        NSApp?.appearance = preferences.theme.appearance
    }

    /// 语言在重新启动后生效；预览与测试不写入真实偏好。
    func setLanguage(_ value: AppLanguage) {
        language = value
        if !preview { value.save(to: defaults) }
    }

    var languageNeedsRestart: Bool { language != AppLanguage.launched }

    /// 等当前进程退出后再打开应用包，避免单实例检查把新进程当成重复启动。
    func relaunch() {
        guard !preview else { return }
        let restart = Process()
        restart.executableURL = URL(fileURLWithPath: "/bin/sh")
        restart.arguments = ["-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$0\"",
                             Bundle.main.bundlePath, String(getpid())]
        do { try restart.run() } catch { return }
        NSApp.terminate(nil)
    }

    /// 读取旧规则与独立显示元数据；损坏数据保留备份供恢复。
    private func loadStoredState() {
        if let data = defaults.data(forKey: "rules.v1") {
            do { rules = try StoredRules.decode(data) }
            catch {
                defaults.set(data, forKey: "rules.v1.invalid-backup")
                errorMessage = String(localized: "error.rules.load")
            }
        }
        if let data = defaults.data(forKey: "networkRules.v1") {
            do { networkRules = try JSONDecoder().decode([String: NetworkRule].self, from: data).mapValues { $0.validated() } }
            catch {
                defaults.set(data, forKey: "networkRules.v1.invalid-backup")
                networkRuleError = String(localized: "error.networkRules.load")
            }
        }
        if let data = defaults.data(forKey: "ruleApplications.v1") {
            savedApplications = (try? JSONDecoder().decode([String: SavedApplication].self, from: data)) ?? [:]
        }
        if let data = defaults.data(forKey: "preferences.v1") {
            preferences = (try? JSONDecoder().decode(AppPreferences.self, from: data)) ?? AppPreferences()
        }
        var discoveredMetadata = false
        for id in Set(rules.keys).union(networkRules.keys) where savedApplications[id] == nil {
            guard let metadata = Self.installedMetadata(id) else { continue }
            savedApplications[id] = metadata
            discoveredMetadata = true
        }
        if discoveredMetadata { persistRules() }
        // 读取已有启用状态；没有有效规则时总开关保持关闭。
        enabled = errorMessage == nil && canEnable &&
            (defaults.object(forKey: "managementEnabled") == nil || defaults.bool(forKey: "managementEnabled"))
    }

    private func persistRules() {
        guard !preview else { return }
        do {
            let ruleData = try StoredRules.encode(rules)
            let metadata = try JSONEncoder().encode(savedApplications)
            defaults.set(ruleData, forKey: "rules.v1")
            defaults.set(metadata, forKey: "ruleApplications.v1")
        } catch {
            errorMessage = String(localized: "error.rules.save \(error.localizedDescription)")
        }
    }

    private func normalizeEnablement() {
        if !canEnable && enabled {
            enabled = false
            if !preview { defaults.set(false, forKey: "managementEnabled") }
        }
    }

    private var displayIsVisible: Bool {
        SamplingPolicy.shouldRefreshDisplay(
            managementOpen: managementIsOpen,
            managementVisible: managementIsOpen && managementWindow?.window?.isMiniaturized == false &&
                managementWindow?.window?.occlusionState.contains(.visible) == true,
            menuVisible: menuWindow?.isVisible == true && menuWindow?.occlusionState.contains(.visible) == true,
            isForeground: NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier,
            onlyInForeground: preferences.refreshOnlyInForeground
        )
    }

    private var controlMonitoringRequired: Bool {
        hasTemporaryPauses || enabled && apps.contains {
            guard let rule = rules[$0.id], rule.isActive else { return false }
            return rule.alwaysLimit || $0.id != foregroundID || $0.isHidden
        }
    }

    private var hasTemporaryPauses: Bool { temporaryActions.values.contains(where: \.isPause) }
    /// 有控制需求时需要跟踪的应用：启用的规则与临时暂停。
    private var controlledIDs: Set<String> {
        Set(rules.filter { $0.value.isActive }.keys).union(temporaryActions.filter { $0.value.isPause }.keys)
    }
    private var needsControl: Bool { (enabled && canEnable) || hasTemporaryPauses }

    /// 在主 actor 上捕获应用列表，在采样 actor 中扫描进程；合并扫描期间的新请求。
    func refresh(force: Bool = false) {
        guard !preview, !sleeping, !isShutdown,
              displayIsVisible || needsControl else { return }
        let displayDue = lastDisplaySample.map {
            NativeProcess.seconds(since: $0) >= preferences.refreshInterval.seconds
        } ?? true
        let display = displayIsVisible && (force || displayDue)
        guard display || controlMonitoringRequired || (force && needsControl) else { return }
        guard refreshTask == nil else {
            pendingRefresh = (pendingRefresh ?? false) || force
            return
        }
        let ids = display ? nil : controlledIDs
        let running = RunningApplication.capture(showSystemApps: display && preferences.showSystemApps, only: ids)
        let includeNetwork = display && preferences.networkActivityVisible
        isRefreshing = true
        refreshTask = Task(priority: .utility) { [weak self, monitor] in
            let snapshot = await monitor.sample(running, includeSystem: display, includeNetwork: includeNetwork)
            guard !Task.isCancelled, let self, !self.sleeping, !self.isShutdown else { return }
            self.refreshTask = nil
            self.isRefreshing = false
            // 扫描期间可能已切到后台，合并结果前再次确认显示需求。
            self.apply(snapshot, updateDisplay: display && self.displayIsVisible)
            self.reconcile()
            if let force = self.pendingRefresh {
                self.pendingRefresh = nil
                self.refresh(force: force)
            }
        }
    }

    /// 合并采样结果，检测应用重启并按刷新用途维护数值与进程成员。
    func apply(_ snapshot: MonitoringSnapshot, updateDisplay: Bool = true) {
        // 读数覆盖的是上一次控制计划生效的时段，按合并前的状态归类。
        let previousStatus = Dictionary(apps.map { ($0.id, $0.status) }, uniquingKeysWith: { first, _ in first })
        savings.observe(snapshot.apps) { [foregroundID] reading in
            Self.savingsPhase(status: previousStatus[reading.id],
                              background: foregroundID != reading.id || reading.isHidden)
        }
        for reading in snapshot.apps {
            let current = Set(reading.samples.filter { reading.primaryPIDs.contains($0.identity.pid) }.map(\.identity))
            if let before = primaryIdentities[reading.id], !before.isEmpty && before.isDisjoint(with: current) {
                backgroundSince[reading.id] = nil
            }
            primaryIdentities[reading.id] = current
        }
        let liveIDs = Set(snapshot.apps.map(\.id))
        let monitoredIDs = controlledIDs
        if updateDisplay {
            backgroundSince = backgroundSince.filter { liveIDs.contains($0.key) }
            primaryIdentities = primaryIdentities.filter { liveIDs.contains($0.key) }
            apps = snapshot.apps
            if let whole = snapshot.system { system = whole }
            networkMonitorStatus = snapshot.networkStatus
            sampledAt = Date()
            lastDisplaySample = NativeProcess.now
            usageHistory.record(apps, at: sampledAt, step: preferences.refreshInterval.seconds)
        } else {
            // 控制刷新只更新成员与执行状态，显示数值仍按独立刷新间隔更新。
            let fresh = Dictionary(uniqueKeysWithValues: snapshot.apps.map { ($0.id, $0) })
            // 窗口不刷新时，受控应用借每 2 秒的控制检查继续记录 CPU、内存和磁盘，不额外扫描；
            // 窗口刷新期间不记录，避免两套采样基线的读数交错。
            if !displayIsVisible {
                usageHistory.record(snapshot.apps.filter { monitoredIDs.contains($0.id) }, at: Date(),
                                    step: 2, removingOthers: false)
            }
            apps = apps.compactMap { old in
                guard monitoredIDs.contains(old.id) else { return old }
                guard var next = fresh[old.id] else { return nil }
                next.network = old.network
                next.processNetwork = old.processNetwork
                next.cpuPercent = old.cpuPercent
                next.gpuPercent = old.gpuPercent
                next.compositingGPUPercent = old.compositingGPUPercent
                next.memoryBytes = old.memoryBytes
                next.readRate = old.readRate
                next.writeRate = old.writeRate
                next.wakeupRate = old.wakeupRate
                next.samples = old.samples
                return next
            }
            let displayedIDs = Set(apps.map(\.id))
            apps.append(contentsOf: snapshot.apps.filter { !displayedIDs.contains($0.id) })
            backgroundSince = backgroundSince.filter { !monitoredIDs.contains($0.key) || liveIDs.contains($0.key) }
            primaryIdentities = primaryIdentities.filter { !monitoredIDs.contains($0.key) || liveIDs.contains($0.key) }
        }
        var metadataChanged = false
        for app in apps where rules[app.id] != nil || networkRules[app.id] != nil {
            let metadata = SavedApplication(app)
            if savedApplications[app.id] != metadata {
                savedApplications[app.id] = metadata
                metadataChanged = true
            }
        }
        if metadataChanged { persistRules() }
        // 应用退出后临时操作失效，重新打开的应用不会被沿用的期限暂停。
        // 快照可能早于临时操作，删除前向系统确认应用确实已退出。
        let running = Set(apps.map(\.id))
        let exited = temporaryActions.keys.filter {
            !running.contains($0) && (preview || NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty)
        }
        if !exited.isEmpty { exited.forEach { temporaryActions[$0] = nil } }
        ensureSelection()
        updateFocus()
    }

    /// 性能限制与暂停计入节省；后台未受限（含等待期、只调音量、总开关关闭）更新基线；其余不计。
    nonisolated static func savingsPhase(status: RuleStatus?, background: Bool) -> SavingsPhase {
        switch status {
        case .budget: .limited(suspended: false)
        case .suspended: .limited(suspended: true)
        case .waiting, .muted, .quieted: .unlimitedBackground
        case .unmanaged, .paused: background ? .unlimitedBackground : .other
        default: .other
        }
    }

    private func updateFocus() {
        if !preview { foregroundID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
        for index in apps.indices where !preview {
            apps[index].isHidden = NSRunningApplication.runningApplications(withBundleIdentifier: apps[index].id)
                .allSatisfy(\.isHidden)
        }
    }

    private func focusChanged() {
        guard !sleeping, !isShutdown else { return }
        guard displayIsVisible || needsControl else {
            // 后台且无控制需求时，只撤销显示定时器，不遍历应用进程状态。
            scheduleRefresh()
            return
        }
        updateFocus()
        // “立即恢复”持续到下次切回该应用，之后照常按规则执行。
        if let front = foregroundID, case .release = temporaryActions[front] { temporaryActions[front] = nil }
        // 从系统设置授权后切回本应用时，重新尝试此前失败的静音。
        if foregroundID == Bundle.main.bundleIdentifier { volume.retry() }
        // 使用缓存计划立即恢复前台应用，再进行异步扫描。
        reconcile()
        // 切走时 reconcile 移除显示定时器；切回时强制更新可见数据。
        refresh(force: true)
    }

    private func membershipChanged(_ id: String?) {
        guard id != Bundle.main.bundleIdentifier else { return }
        if displayIsVisible || (enabled && id.flatMap { rules[$0]?.isActive } == true)
            || id.flatMap({ temporaryActions[$0] })?.isPause == true {
            refresh(force: true)
        }
    }

    /// 根据前台焦点与等待时间生成控制计划，只交给一个工作进程执行。
    private func reconcile() {
        guard !isShutdown else { return }
        let now = NativeProcess.now
        let date = Date()
        if temporaryActions.values.contains(where: { $0.until <= date }) {
            temporaryActions = temporaryActions.filter { $0.value.until > date }
        }
        // 只为临时暂停打开的总开关，在暂停全部结束、又没有有效规则时自动关闭，与删除最后一条规则一致。
        if enabled && !canEnable && !isShutdown {
            enabled = false
            if !preview { defaults.set(false, forKey: "managementEnabled") }
        }
        var plan: [ControlGroup] = []
        var volumes: [String: (pids: Set<Int32>, percent: Double)] = [:]
        for index in apps.indices {
            let id = apps[index].id
            let rule = (rules[id] ?? AppRule()).validated()
            let front = foregroundID == id && !apps[index].isHidden
            if front || !rule.isActive { backgroundSince[id] = nil }
            else if backgroundSince[id] == nil { backgroundSince[id] = now }
            let seconds = backgroundSince[id].map { NativeProcess.seconds(since: $0) } ?? 0
            let status = Policy.status(rule: rule, enabled: enabled,
                                       controllable: apps[index].canControl && (preview || !apps[index].targets.isEmpty),
                                       isForeground: front, isHidden: apps[index].isHidden, backgroundSeconds: seconds,
                                       temporary: temporaryActions[id])
            apps[index].status = status
            if status == .held, !apps[index].targets.isEmpty {
                // 临时暂停与暂停规则一样交给工作进程，写入恢复记录。
                plan.append(ControlGroup(bundleID: id, mode: .suspend, background: false, cpuPercent: rule.cpuPercent,
                                         targets: apps[index].targets))
            } else if Policy.shouldControl(status), !apps[index].targets.isEmpty {
                if rule.needsWorker {
                    // 暂停时降低优先级没有意义，只交给工作进程暂停。
                    plan.append(ControlGroup(bundleID: id, mode: rule.limitsPerformance ? rule.performance : .off,
                                             background: rule.lowersPriority && !rule.suspends,
                                             cpuPercent: rule.cpuPercent, targets: apps[index].targets))
                }
                if rule.adjustsVolume {
                    volumes[id] = (Set(apps[index].targets.map(\.identity.pid)), rule.volumePercent)
                }
            }
        }
        if !preview && !sleeping { controller.update(plan); volume.update(volumes) }
        scheduleRefresh()
    }

    /// 每次只安排一个最早期限；没有显示或控制需求时停用定时器。
    private func scheduleRefresh() {
        // 将暂停状态作为可观察数据发布，切换焦点时无需定时轮询也能更新提示。
        managementDisplayPaused = !preview && managementIsOpen && preferences.refreshOnlyInForeground && !displayIsVisible
        timer?.invalidate()
        timer = nil
        if !preview && (!displayIsVisible || !preferences.networkActivityVisible) {
            Task { await monitor.cancelNetworkSampling() }
        }
        guard !preview, !sleeping, !isShutdown else { return }
        let waiting = apps.filter { $0.status == .waiting }.compactMap { app -> TimeInterval? in
            guard let began = backgroundSince[app.id], let rule = rules[app.id] else { return nil }
            return rule.delaySeconds - NativeProcess.seconds(since: began)
        } + temporaryActions.values.map { max(0.05, $0.until.timeIntervalSinceNow) }
        // 读取尚未返回时按正常显示间隔等待，避免因上次数据过期反复唤醒。
        let remainingDisplay = refreshTask == nil ? (lastDisplaySample.map {
            max(0.05, preferences.refreshInterval.seconds - NativeProcess.seconds(since: $0))
        } ?? preferences.refreshInterval.seconds) : preferences.refreshInterval.seconds
        guard let interval = SamplingPolicy.nextInterval(displayVisible: displayIsVisible,
                                                         displayInterval: remainingDisplay,
                                                         controlMonitoring: controlMonitoringRequired,
                                                         waitingSeconds: waiting) else { return }
        let next = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.reconcile()
                self.refresh()
            }
        }
        next.tolerance = min(0.2, interval * 0.1)
        RunLoop.main.add(next, forMode: .common)
        timer = next
    }

    private func displayVisibilityChanged() {
        guard !isShutdown else { return }
        scheduleRefresh()
        if displayIsVisible { refresh(force: true) }
    }

    func trackMenuWindow(_ window: NSWindow?) {
        menuWindow = window
        if window?.isVisible == true { refresh(force: true) }
        scheduleRefresh()
    }

    func showManagement() {
        if managementWindow == nil { managementWindow = ManagementWindowController(model: self) }
        managementIsOpen = true
        managementWindow?.present()
        refresh(force: true)
        scheduleRefresh()
    }

    func closeManagement() { managementWindow?.close() }

    func managementDidClose() {
        managementIsOpen = false
        updateActivationPolicy()
        scheduleRefresh()
    }

    func showUtility(_ kind: UtilityWindowKind) {
        if utilityWindows[kind] == nil { utilityWindows[kind] = UtilityWindowController(kind: kind, model: self) }
        openUtilities.insert(kind)
        if kind == .statistics { statisticsIsOpen = true; usageStatistics.refresh() }
        utilityWindows[kind]?.present()
    }

    func utilityDidClose(_ kind: UtilityWindowKind) {
        openUtilities.remove(kind)
        if kind == .statistics { statisticsIsOpen = false; usageStatistics.cancel() }
        updateActivationPolicy()
    }

    func closeUtility(_ kind: UtilityWindowKind) { utilityWindows[kind]?.close() }

    private func updateActivationPolicy() {
        NSApp.setActivationPolicy(managementIsOpen || !openUtilities.isEmpty ? .regular : .accessory)
    }

    private func prepareForSleep() {
        sleeping = true
        usageAnalytics.prepareForSleep()
        timer?.invalidate()
        timer = nil
        refreshTask?.cancel()
        refreshTask = nil
        pendingRefresh = nil
        isRefreshing = false
        controller.stop()
        volume.stop()
        backgroundSince.removeAll()
        savings.flush()
        savings.resetTiming()
        // 睡眠时控制进程已恢复全部进程，临时操作随之结束。
        temporaryActions.removeAll()
    }

    private func wake() {
        sleeping = false
        usageAnalytics.wake()
        updateFocus()
        reconcile()
        if displayIsVisible || needsControl { refresh(force: true) }
    }

    /// 停止事件与异步刷新，恢复进程后再清理数据，防止退出阶段重新写入配置。
    func eraseDataAndQuit() -> String? {
        // 清理后关闭窗口时不再自动保存窗口位置。
        managementWindow?.window?.setFrameAutosaveName("")
        savings.stopPersisting()
        stopActivity()
        do {
            if !preview { try AppDataStore.current.erase() }
            NSApp.terminate(nil)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func stopActivity() {
        isShutdown = true
        savings.flush()
        usageAnalytics.stop()
        usageStatistics.cancel()
        updates.cancel()
        timer?.invalidate()
        timer = nil
        refreshTask?.cancel()
        refreshTask = nil
        events = nil
        if !preview { controller.stop(); volume.stop(); Task { await monitor.cancelNetworkSampling() } }
        enabled = false
        temporaryActions.removeAll()
        for index in apps.indices where rules[apps[index].id]?.isActive == true { apps[index].status = .paused }
    }

    /// 正常退出释放窗口与控制器；可重复调用。
    func shutdown() {
        stopActivity()
        managementWindow?.close()
        managementWindow?.window?.contentViewController = nil
        managementWindow = nil
        for controller in utilityWindows.values {
            controller.close()
            controller.window?.contentViewController = nil
        }
        utilityWindows.removeAll()
    }

    static var exampleApps: [AppReading] {
        [
            AppReading(id: "example.editor", name: String(localized: "preview.app.editor"), bundlePaths: [], primaryPIDs: [], targets: [], samples: [],
                       cpuPercent: 12.8, memoryBytes: 712_000_000, readRate: 0, writeRate: 0, canControl: true, isHidden: false),
            AppReading(id: "example.browser", name: String(localized: "preview.app.browser"), bundlePaths: [], primaryPIDs: [], targets: [], samples: [],
                       cpuPercent: 36.2, memoryBytes: 1_480_000_000, readRate: 1024, writeRate: 8192, canControl: true, isHidden: false,
                       wakeupRate: 18.4),
            AppReading(id: "com.apple.finder", name: "Finder", bundlePaths: [], primaryPIDs: [], targets: [], samples: [],
                       cpuPercent: 0.8, memoryBytes: 98_000_000, readRate: 0, writeRate: 0, canControl: false, isHidden: false)
        ]
    }
}
