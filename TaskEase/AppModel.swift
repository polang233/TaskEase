import AppKit
import Foundation
import Observation

@MainActor @Observable
final class AppModel {
    var apps: [AppReading] = []
    var system = SystemReading()
    var rules: [String: AppRule] = [:]
    var enabled = true
    var search = ""
    var selectedID: String?
    var errorMessage: String?
    var sampledAt = Date()
    private(set) var foregroundID: String?
    private var backgroundSince: [String: UInt64] = [:]
    private let monitor = ProcessMonitor()
    private let controller = WorkerController()
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var managementWindow: NSWindow?
    private var sleeping = false
    let preview: Bool

    init(preview: Bool = false) {
        self.preview = preview
        if preview {
            enabled = true
            apps = Self.exampleApps
            system = SystemReading(cpuPercent: 18, gpuPercent: 24, thermalLabel: "正常")
            foregroundID = "example.editor"
            selectedID = apps.first?.id
            return
        }
        _ = Recovery.restore()
        if let data = UserDefaults.standard.data(forKey: "rules.v1") {
            do { rules = try StoredRules.decode(data) }
            catch {
                UserDefaults.standard.set(data, forKey: "rules.v1.invalid-backup")
                errorMessage = "保存的规则无法读取，已保留备份并暂停自动管理。"
                enabled = false
            }
        }
        if errorMessage == nil && UserDefaults.standard.object(forKey: "managementEnabled") != nil {
            enabled = UserDefaults.standard.bool(forKey: "managementEnabled")
        }
        controller.onError = { [weak self] message in
            guard let self else { return }
            self.errorMessage = message
            self.enabled = false
            self.controller.stop()
            self.reconcile()
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.didDeactivateApplicationNotification,
                     NSWorkspace.didHideApplicationNotification,
                     NSWorkspace.didUnhideApplicationNotification,
                     NSWorkspace.activeSpaceDidChangeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshFocus() }
            })
        }
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.sleeping = true; self?.controller.stop() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.sleeping = false; self?.refresh() }
        })
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard application?.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
                Task { @MainActor in self?.refresh() }
            })
        }
        refresh()
        scheduleRefresh()
    }

    var filteredApps: [AppReading] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return apps.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.id.localizedCaseInsensitiveContains(query) }
    }
    var selectedApp: AppReading? { apps.first { $0.id == selectedID } }
    var configuredCount: Int { rules.values.filter { $0.mode != .off }.count }
    var managedCount: Int { apps.filter { Policy.shouldControl($0.status) }.count }
    var helperPID: Int32? { controller.helperPID }

    func setEnabled(_ value: Bool) {
        enabled = value
        if !preview { UserDefaults.standard.set(value, forKey: "managementEnabled") }
        errorMessage = nil
        reconcile()
    }
    func setRule(_ id: String, rule: AppRule) {
        guard apps.first(where: { $0.id == id })?.canControl == true else { return }
        rules[id] = rule.validated()
        if !preview {
            do { UserDefaults.standard.set(try StoredRules.encode(rules), forKey: "rules.v1") }
            catch { errorMessage = "规则保存失败：\(error.localizedDescription)" }
        }
        reconcile()
    }
    func resetRule(_ id: String) { setRule(id, rule: AppRule()) }
    func refresh() {
        guard !preview, !sleeping else { return }
        let (readings, whole) = monitor.sample()
        for reading in readings {
            if let old = apps.first(where: { $0.id == reading.id }) {
                let before = Set(old.samples.filter { old.primaryPIDs.contains($0.identity.pid) }.map(\.identity))
                let current = Set(reading.samples.filter { reading.primaryPIDs.contains($0.identity.pid) }.map(\.identity))
                if !before.isEmpty && before.isDisjoint(with: current) { backgroundSince[reading.id] = nil }
            }
        }
        let liveIDs = Set(readings.map(\.id))
        backgroundSince = backgroundSince.filter { liveIDs.contains($0.key) }
        apps = readings; system = whole; sampledAt = Date()
        if selectedID == nil || !apps.contains(where: { $0.id == selectedID }) { selectedID = apps.first?.id }
        refreshFocus()
    }
    private func refreshFocus() {
        if !preview { foregroundID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
        for index in apps.indices {
            if !preview {
                apps[index].isHidden = NSRunningApplication.runningApplications(withBundleIdentifier: apps[index].id)
                    .allSatisfy { $0.isHidden }
            }
        }
        reconcile()
    }
    private func reconcile() {
        let now = NativeProcess.now
        var plan: [ControlGroup] = []
        for index in apps.indices {
            let id = apps[index].id
            let front = foregroundID == id && !apps[index].isHidden
            if front { backgroundSince[id] = nil }
            else if backgroundSince[id] == nil { backgroundSince[id] = now }
            let seconds = backgroundSince[id].map { NativeProcess.seconds(since: $0) } ?? 0
            let rule = (rules[id] ?? AppRule()).validated()
            let status = Policy.status(rule: rule, enabled: enabled, controllable: apps[index].canControl && (preview || !apps[index].targets.isEmpty),
                                       isForeground: front, isHidden: apps[index].isHidden, backgroundSeconds: seconds)
            apps[index].status = status
            if Policy.shouldControl(status), !apps[index].targets.isEmpty {
                plan.append(ControlGroup(bundleID: id, mode: rule.mode, cpuPercent: rule.cpuPercent,
                                         targets: apps[index].targets))
            }
        }
        if !preview && !sleeping { controller.update(plan); scheduleRefresh() }
    }

    private func scheduleRefresh() {
        guard !preview, !sleeping else { return }
        timer?.invalidate()
        let visible = (NSApp?.windows ?? []).contains { $0.isVisible && !$0.isMiniaturized && $0.frame.height > 80 }
        var interval: TimeInterval = visible || (enabled && configuredCount > 0) ? 2 : 8
        for app in apps where app.status == .waiting {
            if let began = backgroundSince[app.id], let rule = rules[app.id] {
                let remaining = rule.delaySeconds - NativeProcess.seconds(since: began)
                if remaining > 0 { interval = min(interval, max(0.05, remaining)) }
            }
        }
        let next = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(next, forMode: .common)
        timer = next
    }

    func showManagement() {
        if let window = managementWindow {
            window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); refresh(); return
        }
        let view = ContentView(model: self)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 650),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "轻程"; window.minSize = NSSize(width: 760, height: 520)
        window.contentViewController = NSHostingController(rootView: view)
        window.isReleasedWhenClosed = false
        window.center()
        managementWindow = window
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); refresh()
    }
    func shutdown() {
        timer?.invalidate(); timer = nil
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
        controller.stop()
    }
    static var exampleApps: [AppReading] {
        [
            AppReading(id: "example.editor", name: "代码编辑器", bundlePaths: [], primaryPIDs: [], targets: [], samples: [],
                       cpuPercent: 12.8, memoryBytes: 712_000_000, readRate: 0, writeRate: 0, canControl: true, isHidden: false),
            AppReading(id: "example.browser", name: "网页浏览器", bundlePaths: [], primaryPIDs: [], targets: [], samples: [],
                       cpuPercent: 36.2, memoryBytes: 1_480_000_000, readRate: 1024, writeRate: 8192, canControl: true, isHidden: false),
            AppReading(id: "com.apple.finder", name: "Finder", bundlePaths: [], primaryPIDs: [], targets: [], samples: [],
                       cpuPercent: 0.8, memoryBytes: 98_000_000, readRate: 0, writeRate: 0, canControl: false, isHidden: false)
        ]
    }
}

import SwiftUI
