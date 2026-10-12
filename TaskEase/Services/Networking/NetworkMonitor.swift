import Foundation
import Darwin

/// 在 actor 中管理限时网络快照进程。关闭数据窗口后取消采样，不留下常驻 nettop。
actor NetworkMonitor {
    private var process: Process?
    private var identity: ProcessIdentity?
    private var continuation: CheckedContinuation<[Int32: NetworkByteCount]?, Never>?
    private var outputHandle: FileHandle?
    private var deadline: Task<Void, Never>?
    private var generation = 0
    private var requestedPIDs: Set<Int32> = []

    func sample(pids: Set<Int32>) async -> [Int32: NetworkByteCount]? {
        guard !pids.isEmpty else { return [:] }
        guard process == nil, !Task.isCancelled else { return nil }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                requestedPIDs = pids
                generation += 1
                let request = generation
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("TaskEase.Network.\(UUID().uuidString).csv")
                let child = Process()
                do {
                    guard FileManager.default.createFile(atPath: url.path, contents: nil,
                                                         attributes: [.posixPermissions: 0o600]) else {
                        throw CocoaError(.fileWriteUnknown)
                    }
                    let handle = try FileHandle(forUpdating: url)
                    outputHandle = handle
                    // 使用匿名文件描述符承接有限输出，进程崩溃也不会留下快照文件。
                    try FileManager.default.removeItem(at: url)
                    child.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
                    // 一次读取系统汇总，随后只保留请求的成员；目标数量不影响命令参数长度。
                    child.arguments = ["-P", "-L", "1", "-n", "-x", "-J", "bytes_in,bytes_out"]
                    child.standardOutput = handle
                    child.standardError = FileHandle.nullDevice
                    child.terminationHandler = { _ in Task { await self.finished(request: request) } }
                    try child.run()
                    process = child
                    identity = NativeProcess.identity(child.processIdentifier)
                    deadline = Task {
                        do { try await Task.sleep(for: .seconds(1.5)) }
                        catch { return }
                        self.cancel()
                    }
                } catch { finish(result: nil) }
            }
        } onCancel: { Task { await self.cancel() } }
    }

    /// 只结束自己创建且身份仍匹配的读取进程；实际应用的联网状态不受影响。
    func cancel() {
        guard let process else { return }
        deadline?.cancel()
        if process.isRunning, let identity, NativeProcess.identity(identity.pid) == identity { process.terminate() }
        let expected = identity
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            if let expected, NativeProcess.identity(expected.pid) == expected { kill(expected.pid, SIGKILL) }
        }
    }

    private func finished(request: Int) {
        guard request == generation, let child = process else { return }
        var counters: [Int32: NetworkByteCount]?
        if child.terminationStatus == 0, let handle = outputHandle,
           let size = try? handle.seekToEnd(), size <= 1_048_576 {
            do {
                try handle.seek(toOffset: 0)
                if let data = try handle.read(upToCount: Int(size)),
                   let text = String(data: data, encoding: .utf8) {
                    counters = try NetworkCSV.parse(text).filter { requestedPIDs.contains($0.key) }
                }
            } catch { counters = nil }
        }
        finish(result: counters)
    }

    private func finish(result: [Int32: NetworkByteCount]?) {
        deadline?.cancel(); deadline = nil
        try? outputHandle?.close(); outputHandle = nil
        process = nil
        identity = nil
        requestedPIDs.removeAll()
        let pending = continuation
        continuation = nil
        pending?.resume(returning: result)
    }
}
