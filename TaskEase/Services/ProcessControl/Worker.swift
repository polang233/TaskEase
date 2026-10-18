import Foundation
import Darwin

/// 保存一个应用进程组的采样基线与共享 CPU 额度。
private final class WorkerGroup {
    var config: ControlGroup
    var previous: [ProcessIdentity: UInt64] = [:]
    var lastWall = NativeProcess.now
    var credit = BudgetCredit()
    init(_ config: ControlGroup) { self.config = config }
}

/// 独立执行控制计划，失联、关闭或解析失败时恢复本工具施加的状态。
enum NativeWorker {
    static func run(testing: Bool = false) {
        te_install_worker_signals()
        guard let workerID = NativeProcess.identity(getpid()),
              let controllerID = NativeProcess.identity(getppid()) else { return }
        do { try FileManager.default.createDirectory(at: Recovery.directory, withIntermediateDirectories: true) }
        catch { return }
        let lockURL = Recovery.directory.appendingPathComponent(testing ? "test-worker.lock" : "worker.lock")
        let lock = open(lockURL.path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard lock >= 0, flock(lock, LOCK_EX | LOCK_NB) == 0 else {
            if lock >= 0 { close(lock) }
            emit(WorkerEvent(kind: "error", message: String(localized: "worker.busy")))
            return
        }
        defer { flock(lock, LOCK_UN); close(lock) }
        // 接收新计划前先恢复已经失联的旧工作进程记录。
        _ = Recovery.restore(testing: testing)
        var journal = RecoveryRecord(worker: workerID, controller: controllerID)
        var groups: [String: WorkerGroup] = [:]
        var lowered: [ProcessIdentity: ControlTarget] = [:]
        var maySuspend: [ProcessIdentity: ControlTarget] = [:]
        var stopped: Set<ProcessIdentity> = []
        var excluded: Set<ProcessIdentity> = []
        var savedBackground: Set<ProcessIdentity> = []
        var savedSuspension: Set<ProcessIdentity> = []
        var hasSavedOwnership = false
        var lastMessage = NativeProcess.now
        var input = Data()
        var bytes = [UInt8](repeating: 0, count: 16384)
        let decoder = JSONDecoder()
        var closing = false
        var failed = false
        let ownBundle = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        let inputFD = STDIN_FILENO
        let oldFlags = fcntl(inputFD, F_GETFL)
        _ = fcntl(inputFD, F_SETFL, oldFlags | O_NONBLOCK)

        func saveOwnership() throws {
            let backgroundKeys = Set(lowered.keys), suspensionKeys = Set(maySuspend.keys)
            guard !hasSavedOwnership || backgroundKeys != savedBackground || suspensionKeys != savedSuspension else { return }
            journal.background = Array(lowered.values)
            journal.suspension = Array(maySuspend.values)
            try Recovery.save(journal, testing: testing)
            savedBackground = backgroundKeys; savedSuspension = suspensionKeys; hasSavedOwnership = true
        }
        func valid(_ target: ControlTarget) -> Bool {
            guard target.identity != workerID, target.identity != controllerID,
                  NativeProcess.matches(target) else { return false }
            if target.bundlePath == ownBundle {
                return testing && NativeProcess.sample(target.identity.pid)?.parentPID == controllerID.pid
            }
            return true
        }
        func release(_ target: ControlTarget) {
            if stopped.contains(target.identity) {
                _ = NativeProcess.signal(target, number: SIGCONT)
                stopped.remove(target.identity)
            }
            maySuspend.removeValue(forKey: target.identity)
            if lowered.removeValue(forKey: target.identity) != nil {
                _ = NativeProcess.background(target, enabled: false)
            }
            excluded.remove(target.identity)
        }
        func apply(_ message: ControlMessage) throws {
            lastMessage = NativeProcess.now
            if message.shutdown { closing = true; return }
            guard message.groups.count <= 128 else { throw WorkerFailure.invalidPlan }
            var desired: [String: ControlGroup] = [:]
            for group in message.groups {
                guard group.mode != .gentle, group.mode != .off || group.background, group.cpuPercent.isFinite,
                      group.cpuPercent >= 5, group.cpuPercent <= 200,
                      group.targets.count <= 256 else { throw WorkerFailure.invalidPlan }
                let targets = group.targets.filter(valid)
                if !targets.isEmpty {
                    desired[group.bundleID] = ControlGroup(bundleID: group.bundleID, mode: group.mode,
                                                          background: group.background,
                                                          cpuPercent: group.cpuPercent, targets: targets)
                }
            }
            let keep = Set(desired.values.flatMap { $0.targets.map(\.identity) })
            for target in Array(lowered.values) + Array(maySuspend.values) where !keep.contains(target.identity) {
                release(target)
            }
            for (id, group) in Array(groups) where desired[id] == nil {
                for target in group.config.targets { release(target) }
                groups.removeValue(forKey: id)
            }
            for (id, config) in desired {
                if let group = groups[id], group.config.mode == config.mode,
                   group.config.background == config.background,
                   group.config.cpuPercent == config.cpuPercent {
                    group.config = config
                } else {
                    if let old = groups[id] { for target in old.config.targets { release(target) } }
                    groups[id] = WorkerGroup(config)
                }
            }
            try saveOwnership()
        }

        emit(WorkerEvent(kind: "ready", message: String(localized: "worker.ready")))
        defer {
            // 以持久归属记录恢复，包含异常发生前已记录的暂停。
            _ = Recovery.restore(testing: testing, force: true)
            emit(WorkerEvent(kind: "restored", message: String(localized: "worker.restored")))
        }
        while !closing && !failed && te_worker_should_exit() == 0 {
            if NativeProcess.seconds(since: lastMessage) > 3 || !NativeProcess.isAlive(controllerID) { break }
            var descriptor = pollfd(fd: inputFD, events: Int16(POLLIN | POLLHUP), revents: 0)
            let result = poll(&descriptor, 1, groups.values.contains { $0.config.mode == .budget } ? 50 : 150)
            if result > 0 {
                while true {
                    let count = read(inputFD, &bytes, bytes.count)
                    if count > 0 {
                        input.append(contentsOf: bytes.prefix(count))
                        if input.count > 1_048_576 { failed = true; break }
                    } else {
                        if count == 0 { closing = true }
                        break
                    }
                }
                while let newline = input.firstIndex(of: 10) {
                    let line = Data(input[..<newline])
                    input.removeSubrange(...newline)
                    do { try apply(decoder.decode(ControlMessage.self, from: line)) }
                    catch {
                        emit(WorkerEvent(kind: "error", message: String(localized: "worker.planFailed")))
                        failed = true; break
                    }
                }
            }
            if closing || failed { break }
            let now = NativeProcess.now
            for group in groups.values {
                var current: [ProcessIdentity: UInt64] = [:]
                var members: [ControlTarget] = []
                var used: UInt64 = 0
                for target in group.config.targets {
                    guard valid(target), let sample = NativeProcess.sample(target.identity.pid),
                          sample.identity == target.identity else { release(target); continue }
                    if excluded.contains(target.identity) { continue }
                    // BSD 暂停状态 SSTOP 为 4；跳过已经由其他工具暂停的进程。
                    if sample.status == 4 && !stopped.contains(target.identity) {
                        excluded.insert(target.identity); continue
                    }
                    if group.config.mode == .suspend {
                        // 整组保持暂停，直到计划移除该组；归属先写入恢复日志再发送信号。
                        if !stopped.contains(target.identity) {
                            if maySuspend[target.identity] == nil {
                                maySuspend[target.identity] = target
                                do { try saveOwnership() } catch { failed = true; break }
                            }
                            if NativeProcess.signal(target, number: SIGSTOP) {
                                stopped.insert(target.identity)
                            } else if NativeProcess.identity(target.identity.pid) == target.identity {
                                emit(WorkerEvent(kind: "error", message: String(localized: "worker.suspendDenied")))
                                failed = true; break
                            }
                        }
                        continue
                    }
                    if group.config.background,
                       lowered[target.identity] == nil && te_get_background(target.identity.pid) == 0 {
                        lowered[target.identity] = target
                        do { try saveOwnership() } catch { failed = true; break }
                        if !NativeProcess.background(target, enabled: true) {
                            lowered.removeValue(forKey: target.identity)
                            emit(WorkerEvent(kind: "error", message: String(localized: "worker.backgroundDenied")))
                        }
                    }
                    if group.config.mode == .budget {
                        members.append(target)
                        current[target.identity] = sample.cpuTicks
                        if let before = group.previous[target.identity], sample.cpuTicks >= before {
                            used += sample.cpuTicks - before
                        }
                    }
                }
                if group.config.mode == .budget {
                    let elapsed = now >= group.lastWall ? now - group.lastWall : 0
                    let fraction = group.config.cpuPercent / 100
                    let shouldStop = group.credit.update(elapsedTicks: elapsed, usedTicks: used,
                                                        fraction: fraction,
                                                        burstTicks: NativeProcess.ticksPerSecond * 0.1 * fraction)
                    group.previous = current; group.lastWall = now
                    for target in members {
                        if shouldStop && !stopped.contains(target.identity) {
                            if maySuspend[target.identity] == nil {
                                maySuspend[target.identity] = target
                                do { try saveOwnership() } catch { failed = true; break }
                            }
                            if NativeProcess.signal(target, number: SIGSTOP) {
                                stopped.insert(target.identity)
                            } else if NativeProcess.identity(target.identity.pid) == target.identity {
                                emit(WorkerEvent(kind: "error", message: String(localized: "worker.suspendDenied")))
                                failed = true; break
                            }
                        } else if !shouldStop && stopped.contains(target.identity) {
                            _ = NativeProcess.signal(target, number: SIGCONT)
                            stopped.remove(target.identity)
                        }
                    }
                }
            }
        }
    }

    private enum WorkerFailure: Error { case invalidPlan }
    private static func emit(_ event: WorkerEvent) {
        guard var data = try? JSONEncoder().encode(event) else { return }
        data.append(10)
        try? FileHandle.standardOutput.write(contentsOf: data)
    }
}

/// 负责工作进程的启动、心跳传输、结束等待和主应用补偿恢复。
@MainActor
final class WorkerController {
    private var process: Process?
    /// 计划清空后正在退出的工作进程；退出在后台等待，不阻塞主线程。
    private var retiring: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var outputData = Data()
    private var stopping = false
    private var generation = 0
    private let testing: Bool
    init(testing: Bool = false) { self.testing = testing }
    var onError: ((String) -> Void)?
    var helperPID: Int32? { process?.isRunning == true ? process?.processIdentifier : nil }

    /// 有控制需求才启动工作进程；空计划让工作进程自行恢复并退出，主线程不等待。
    func update(_ groups: [ControlGroup]) {
        guard !groups.isEmpty else { retire(); return }
        if process?.isRunning != true {
            // 旧进程仍持有控制锁时，新进程会启动失败；这种少见情况下同步等它退出。
            if let old = retiring { finish(old) }
            _ = Recovery.restore(testing: testing)
            guard let executable = Bundle.main.executableURL else { return }
            generation += 1
            let currentGeneration = generation
            let child = Process()
            let incoming = Pipe(), outgoing = Pipe()
            child.executableURL = executable
            child.arguments = [testing ? "--self-test-worker" : "--limiter-worker"]
            child.standardInput = incoming; child.standardOutput = outgoing
            child.standardError = FileHandle.nullDevice
            child.terminationHandler = { [weak self] ended in
                Task { @MainActor in self?.ended(ended, generation: currentGeneration) }
            }
            outgoing.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                if !data.isEmpty { Task { @MainActor in self?.receive(data, generation: currentGeneration) } }
            }
            do {
                try child.run()
                process = child; input = incoming.fileHandleForWriting
                output = outgoing.fileHandleForReading
            } catch {
                outgoing.fileHandleForReading.readabilityHandler = nil
                onError?(String(localized: "worker.launchFailed \(error.localizedDescription)"))
                return
            }
        }
        send(ControlMessage(groups: groups))
    }
    private func receive(_ data: Data, generation expected: Int) {
        guard generation == expected else { return }
        outputData.append(data)
        while let newline = outputData.firstIndex(of: 10) {
            let line = Data(outputData[..<newline])
            outputData.removeSubrange(...newline)
            if let event = try? JSONDecoder().decode(WorkerEvent.self, from: line), event.kind == "error" {
                onError?(event.message)
            }
        }
    }
    private func send(_ message: ControlMessage) {
        guard var data = try? JSONEncoder().encode(message) else { return }
        data.append(10)
        do { try input?.write(contentsOf: data) }
        catch {
            onError?(String(localized: "worker.disconnected"))
            if !stopping { stop() }
        }
    }
    private func ended(_ child: Process, generation expected: Int) {
        if child === retiring {
            retiring = nil
            _ = Recovery.restore(testing: testing)
            return
        }
        guard generation == expected, process != nil else { return }
        output?.readabilityHandler = nil
        input = nil; output = nil; process = nil; outputData.removeAll()
        _ = Recovery.restore(testing: testing)
        if !stopping { onError?(String(localized: "worker.ended")) }
    }

    /// 发送关闭消息并断开连接，退出由终止回调收尾；超时后依次结束、强制结束。
    private func retire() {
        guard let child = process else {
            if retiring == nil { _ = Recovery.restore(testing: testing) }
            return
        }
        send(ControlMessage(groups: [], shutdown: true))
        try? input?.close()
        output?.readabilityHandler = nil
        process = nil; input = nil; output = nil; outputData.removeAll()
        generation += 1
        retiring = child
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, self.retiring === child, child.isRunning else { return }
            child.terminate()
            try? await Task.sleep(for: .milliseconds(500))
            if self.retiring === child, child.isRunning { kill(child.processIdentifier, SIGKILL) }
        }
    }

    /// 同步等待退出，仅用于启动新进程前、睡眠、退出和数据清理。
    private func finish(_ child: Process) {
        let deadline = Date().addingTimeInterval(1)
        while child.isRunning && Date() < deadline { usleep(10_000) }
        if child.isRunning { child.terminate() }
        let finalDeadline = Date().addingTimeInterval(0.5)
        while child.isRunning && Date() < finalDeadline { usleep(10_000) }
        if child.isRunning { kill(child.processIdentifier, SIGKILL) }
        child.waitUntilExit()
        if retiring === child { retiring = nil }
        _ = Recovery.restore(testing: testing)
    }

    /// 请求正常恢复并等待工作进程完全退出，数据清理才能安全移除恢复目录。
    func stop() {
        guard !stopping else { return }
        if let old = retiring { finish(old) }
        guard let child = process else { _ = Recovery.restore(testing: testing); return }
        stopping = true
        send(ControlMessage(groups: [], shutdown: true))
        try? input?.close()
        output?.readabilityHandler = nil
        finish(child)
        process = nil; input = nil; output = nil; outputData.removeAll()
        generation += 1
        stopping = false
    }
}
