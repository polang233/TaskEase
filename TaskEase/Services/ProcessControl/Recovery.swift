import Foundation
import Darwin

/// 保存控制归属日志，在控制器失联或应用重启后恢复进程。
enum Recovery {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "TaskEase", isDirectory: true)
    }
    static func url(testing: Bool = false) -> URL {
        directory.appendingPathComponent(testing ? "test-recovery.json" : "recovery.json")
    }
    static func read(testing: Bool = false) -> RecoveryRecord? {
        guard let data = try? Data(contentsOf: url(testing: testing)) else { return nil }
        return try? JSONDecoder().decode(RecoveryRecord.self, from: data)
    }
    static func save(_ record: RecoveryRecord, testing: Bool = false) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(record)
        try data.write(to: url(testing: testing), options: .atomic)
    }
    @discardableResult static func restore(testing: Bool = false, force: Bool = false) -> Int {
        guard let record = read(testing: testing), record.worker.uid == geteuid() else { return 0 }
        guard force || !NativeProcess.isAlive(record.worker) else { return 0 }
        var restored = 0
        for target in record.suspension where NativeProcess.identity(target.identity.pid) == target.identity {
            if NativeProcess.signal(target, number: SIGCONT) { restored += 1 }
        }
        for target in record.background where NativeProcess.identity(target.identity.pid) == target.identity {
            if NativeProcess.background(target, enabled: false) { restored += 1 }
        }
        try? FileManager.default.removeItem(at: url(testing: testing))
        return restored
    }
}
