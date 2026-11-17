import Foundation

/// 节省记录保存在本应用的 Application Support 目录（与恢复记录同一目录），随“清除数据并退出”一并删除。
struct SavingsStore: Sendable {
    let url: URL

    static var current: SavingsStore {
        SavingsStore(url: Recovery.directory.appendingPathComponent("savings.v1.json"))
    }

    /// 文件缺失时返回空记录；损坏时保留备份并重新开始，不影响规则执行。
    func load() -> SavingsLedger {
        guard let data = try? Data(contentsOf: url) else { return SavingsLedger() }
        do {
            return try decode(data)
        } catch {
            try? data.write(to: url.appendingPathExtension("invalid-backup"), options: .atomic)
            return SavingsLedger()
        }
    }

    func save(_ ledger: SavingsLedger) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try encoder.encode(ledger).write(to: url, options: .atomic)
    }
}

extension SavingsStore {
    /// 与 `save` 对应的解码设置。
    func decode(_ data: Data) throws -> SavingsLedger {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(SavingsLedger.self, from: data)
    }
}
