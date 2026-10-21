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
    private(set) var isRefreshing = false
    private(set) var managementIsOpen = false
    private(set) var managementDisplayPaused = false
    private(set) var statisticsIsOpen = false
    private(set) var foregroundID: String?
    let preview: Bool
    let usageAnalytics: UsageAnalytics
    let usageStatistics: UsageStatisticsModel
    let updates: UpdateChecker

    @ObservationIgnored private var savedApplications: [String: SavedApplication] = [:]
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
        if preview {
            apps = Self.exampleApps
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
    var canEnable: Bool { configuredCount > 0 && !isShutdown }
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
        if rules[id]?.isActive != true && validated.isActive { backgroundSince[id] = nil }
        if validated.adjustsVolume && rules[id]?.adjustsVolume != true { volume.retry() }
        rules[id] = validated
        savedApplications[id] = SavedApplication(application)
        persistRules()
        normalizeEnablement()
        reconcile()
        refresh(force: true)
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
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { continue }
            let bundle = Bundle(url: url)
            let name = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ??
                url.deletingPathExtension().lastPathComponent
            savedApplications[id] = SavedApplication(name: name,
                                                      bundlePaths: [url.resolvingSymlinksInPath().path])
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
            managementVisible: managementIsOpen && managementWindow?.window?.isMiniaturized == false &&
                managementWindow?.window?.occlusionState.contains(.visible) == true,
            menuVisible: menuWindow?.isVisible == true && menuWindow?.occlusionState.contains(.visible) == true,
            isForeground: NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier,
            onlyInForeground: preferences.refreshOnlyInForeground
        )
    }

    private var controlMonitoringRequired: Bool {
        enabled && apps.contains {
            guard let rule = rules[$0.id], rule.isActive else { return false }
            return rule.alwaysLimit || $0.id != foregroundID || $0.isHidden
        }
    }

    /// 在主 actor 上捕获应用列表，在采样 actor 中扫描进程；合并扫描期间的新请求。
    func refresh(force: Bool = false) {
        guard !preview, !sleeping, !isShutdown,
              displayIsVisible || (enabled && canEnable) else { return }
        let displayDue = lastDisplaySample.map {
            NativeProcess.seconds(since: $0) >= preferences.refreshInterval.seconds
        } ?? true
        let display = displayIsVisible && (force || displayDue)
        guard display || controlMonitoringRequired || (force && enabled && canEnable) else { return }
        guard refreshTask == nil else {
            pendingRefresh = (pendingRefresh ?? false) || force
            return
        }
        let ids = display ? nil : Set(rules.filter { $0.value.isActive }.keys)
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
        for reading in snapshot.apps {
            let current = Set(reading.samples.filter { reading.primaryPIDs.contains($0.identity.pid) }.map(\.identity))
            if let before = primaryIdentities[reading.id], !before.isEmpty && before.isDisjoint(with: current) {
                backgroundSince[reading.id] = nil
            }
            primaryIdentities[reading.id] = current
        }
        let liveIDs = Set(snapshot.apps.map(\.id))
        let monitoredIDs = Set(rules.filter { $0.value.isActive }.keys)
        if updateDisplay {
            backgroundSince = backgroundSince.filter { liveIDs.contains($0.key) }
            primaryIdentities = primaryIdentities.filter { liveIDs.contains($0.key) }
            apps = snapshot.apps
            if let whole = snapshot.system { system = whole }
            networkMonitorStatus = snapshot.networkStatus
            sampledAt = Date()
            lastDisplaySample = NativeProcess.now
        } else {
            // 控制刷新只更新成员与执行状态，显示数值仍按独立刷新间隔更新。
            let fresh = Dictionary(uniqueKeysWithValues: snapshot.apps.map { ($0.id, $0) })
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
        ensureSelection()
        updateFocus()
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
        guard displayIsVisible || (enabled && canEnable) else {
            // 后台且无控制需求时，只撤销显示定时器，不遍历应用进程状态。
            scheduleRefresh()
            return
        }
        updateFocus()
        // 从系统设置授权后切回本应用时，重新尝试此前失败的静音。
        if foregroundID == Bundle.main.bundleIdentifier { volume.retry() }
        // 使用缓存计划立即恢复前台应用，再进行异步扫描。
        reconcile()
        // 切走时 reconcile 移除显示定时器；切回时强制更新可见数据。
        refresh(force: true)
    }

    private func membershipChanged(_ id: String?) {
        guard id != Bundle.main.bundleIdentifier else { return }
        if displayIsVisible || (enabled && id.flatMap { rules[$0]?.isActive } == true) {
            refresh(force: true)
        }
    }

    /// 根据前台焦点与等待时间生成控制计划，只交给一个工作进程执行。
    private func reconcile() {
        guard !isShutdown else { return }
        let now = NativeProcess.now
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
                                       isForeground: front, isHidden: apps[index].isHidden, backgroundSeconds: seconds)
            apps[index].status = status
            if Policy.shouldControl(status), !apps[index].targets.isEmpty {
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
        }
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
    }

    private func wake() {
        sleeping = false
        usageAnalytics.wake()
        updateFocus()
        reconcile()
        if displayIsVisible || (enabled && canEnable) { refresh(force: true) }
    }

    /// 停止事件与异步刷新，恢复进程后再清理数据，防止退出阶段重新写入配置。
    func eraseDataAndQuit() -> String? {
        // 清理后关闭窗口时不再自动保存窗口位置。
        managementWindow?.window?.setFrameAutosaveName("")
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
