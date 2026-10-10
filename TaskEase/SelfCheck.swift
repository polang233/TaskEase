import Foundation
import Darwin

@MainActor
enum SelfCheck {
    static func snapshot() {
        let monitor = ProcessMonitor()
        _ = monitor.sample()
        usleep(500_000)
        let (apps, system) = monitor.sample()
        let rows: [[String: Any]] = apps.map { app in
            ["id": app.id, "name": app.name, "cpuPercent": app.cpuPercent ?? 0,
             "memoryBytes": app.memoryBytes, "processCount": app.targets.count,
             "controllable": app.canControl]
        }
        let report: [String: Any] = ["scope": "read_only_snapshot",
            "appCount": apps.count, "apps": rows,
            "systemCPU": system.cpuPercent ?? -1, "gpuDriverPercent": system.gpuPercent ?? -1,
            "thermal": system.thermalLabel]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: data, encoding: .utf8) { print(text) }
    }

    static func burn() {
        let finish = NativeProcess.now + UInt64(NativeProcess.ticksPerSecond * 20)
        var value: UInt64 = 17
        while NativeProcess.now < finish {
            for _ in 0..<8192 { value = value &* 6364136223846793005 &+ 1 }
        }
        print(value)
    }

    private static func pump(_ seconds: Double, heartbeat: (() -> Void)? = nil) {
        let finish = Date().addingTimeInterval(seconds)
        var next = Date()
        while Date() < finish {
            if Date() >= next {
                heartbeat?()
                next = Date().addingTimeInterval(0.4)
            }
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
    }
    private static func usage(_ target: ControlTarget, seconds: Double, heartbeat: (() -> Void)? = nil) -> Double {
        guard let first = NativeProcess.sample(target.identity.pid) else { return 0 }
        let wall = NativeProcess.now
        pump(seconds, heartbeat: heartbeat)
        guard let last = NativeProcess.sample(target.identity.pid), last.cpuTicks >= first.cpuTicks else { return 0 }
        return 100 * Double(last.cpuTicks - first.cpuTicks) / Double(NativeProcess.now - wall)
    }

    static func run() -> Bool {
        guard let executable = Bundle.main.executableURL else { return false }
        let child = Process()
        child.executableURL = executable
        child.arguments = ["--burner"]
        child.standardOutput = FileHandle.nullDevice; child.standardError = FileHandle.nullDevice
        do { try child.run() } catch { return false }
        let controller = WorkerController(testing: true)
        var extraChildren: [(Process, ControlTarget)] = []
        defer {
            controller.stop()
            for (extra, target) in extraChildren {
                _ = NativeProcess.signal(target, number: SIGCONT)
                if extra.isRunning { extra.terminate(); extra.waitUntilExit() }
            }
            if let identity = NativeProcess.identity(child.processIdentifier),
               let path = NativeProcess.path(child.processIdentifier) {
                _ = NativeProcess.signal(ControlTarget(identity: identity, executablePath: path,
                    bundlePath: Bundle.main.bundleURL.path), number: SIGCONT)
            }
            if child.isRunning { child.terminate(); child.waitUntilExit() }
            _ = Recovery.restore(testing: true)
        }
        pump(0.2)
        guard let identity = NativeProcess.identity(child.processIdentifier),
              let path = NativeProcess.path(child.processIdentifier) else { return false }
        let target = ControlTarget(identity: identity, executablePath: path,
                                   bundlePath: Bundle.main.bundleURL.resolvingSymlinksInPath().path)
        let budget = ControlGroup(bundleID: "TaskEase.self-check", mode: .budget, cpuPercent: 20, targets: [target])
        let gentle = ControlGroup(bundleID: "TaskEase.self-check", mode: .gentle, cpuPercent: 20, targets: [target])
        var results: [String: Any] = ["scope": "owned_test_child_only", "cpu_basis": "one_core"]

        let baseline = usage(target, seconds: 0.8)
        controller.update([budget])
        pump(0.25)
        let limited = usage(target, seconds: 2.5) { controller.update([budget]) }
        controller.update([])
        pump(0.15)
        let resumed = usage(target, seconds: 0.8)
        results["baseline_cpu_percent"] = baseline
        results["limited_cpu_percent"] = limited
        results["restored_cpu_percent"] = resumed

        controller.update([gentle])
        pump(0.25)
        let gentleApplied = te_get_background(identity.pid) == 1
        controller.update([])
        pump(0.15)
        let gentleRestored = te_get_background(identity.pid) == 0
        results["gentle_applied"] = gentleApplied
        results["gentle_restored"] = gentleRestored

        // An alive controller without renewals models a stalled main app.
        controller.update([budget])
        pump(3.7)
        let leaseRecovered = NativeProcess.sample(identity.pid)?.status != 4 &&
            controller.helperPID == nil && Recovery.read(testing: true) == nil
        results["lease_timeout_restored"] = leaseRecovered

        controller.update([budget])
        let deadline = Date().addingTimeInterval(1.2)
        while Date() < deadline && NativeProcess.sample(identity.pid)?.status != 4 {
            pump(0.06) { controller.update([budget]) }
        }
        let wasStopped = NativeProcess.sample(identity.pid)?.status == 4
        if let workerPID = controller.helperPID { kill(workerPID, SIGKILL) }
        pump(0.5)
        let crashRecovered = wasStopped && NativeProcess.sample(identity.pid)?.status != 4 &&
            Recovery.read(testing: true) == nil
        results["worker_crash_restored"] = crashRecovered

        let second = Process()
        second.executableURL = executable
        second.arguments = ["--burner"]
        second.standardOutput = FileHandle.nullDevice; second.standardError = FileHandle.nullDevice
        var groupCPU = 0.0
        var groupRestored = false
        do {
            try second.run()
            pump(0.15)
            if let secondID = NativeProcess.identity(second.processIdentifier),
               let secondPath = NativeProcess.path(second.processIdentifier) {
                let secondTarget = ControlTarget(identity: secondID, executablePath: secondPath, bundlePath: target.bundlePath)
                extraChildren.append((second, secondTarget))
                let group = ControlGroup(bundleID: "TaskEase.self-check", mode: .budget, cpuPercent: 20,
                                         targets: [target, secondTarget])
                controller.update([group]); pump(0.2)
                let before = (NativeProcess.sample(identity.pid)?.cpuTicks ?? 0) +
                    (NativeProcess.sample(secondID.pid)?.cpuTicks ?? 0)
                let wall = NativeProcess.now
                pump(2.5) { controller.update([group]) }
                let after = (NativeProcess.sample(identity.pid)?.cpuTicks ?? 0) +
                    (NativeProcess.sample(secondID.pid)?.cpuTicks ?? 0)
                groupCPU = after >= before ? 100 * Double(after-before) / Double(NativeProcess.now-wall) : 0
                controller.update([]); pump(0.2)
                groupRestored = NativeProcess.sample(identity.pid)?.status != 4 &&
                    NativeProcess.sample(secondID.pid)?.status != 4
            } else {
                second.terminate(); second.waitUntilExit()
            }
        } catch {}
        results["two_process_group_cpu_percent"] = groupCPU
        results["group_restored"] = groupRestored

        let passed = groupCPU >= 8 && groupCPU <= 35 && groupRestored && baseline > 55 && limited >= 8 && limited <= 35 && resumed > 55 &&
            gentleApplied && gentleRestored && leaseRecovered && crashRecovered
        results["passed"] = passed
        if let data = try? JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: data, encoding: .utf8) { print(text) }
        return passed
    }
}
