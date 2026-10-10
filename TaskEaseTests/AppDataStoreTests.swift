import Foundation
import Testing
@testable import TaskEase

/// 使用独立偏好域和临时目录验证清理范围与重复执行。
struct AppDataStoreTests {
    @Test func eraseRemovesOwnedDataAndPreservesAdjacentData() throws {
        let domain = "TaskEase.DataTest." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(domain)
        defer { try? FileManager.default.removeItem(at: root) }
        let owned = root.appendingPathComponent("owned")
        let adjacent = root.appendingPathComponent("another-app.txt")
        try FileManager.default.createDirectory(at: owned, withIntermediateDirectories: true)
        try Data("rules".utf8).write(to: owned.appendingPathComponent("rules.json"))
        try Data("keep".utf8).write(to: adjacent)
        defaults.set(Data("saved".utf8), forKey: "rules.v1")
        defaults.set(true, forKey: "managementEnabled")
        let store = AppDataStore(domain: domain, defaults: defaults, directories: [owned])
        try store.erase()
        #expect(!FileManager.default.fileExists(atPath: owned.path))
        #expect(defaults.persistentDomain(forName: domain)?.isEmpty != false)
        #expect(try String(contentsOf: adjacent, encoding: .utf8) == "keep")
        try store.erase()
    }

    @Test func directoryFailureIsReportedBeforePreferencesAreRemoved() throws {
        let domain = "TaskEase.DataTest." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(domain)
        let owned = root.appendingPathComponent("owned")
        try FileManager.default.createDirectory(at: owned, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
            try? FileManager.default.removeItem(at: root)
        }
        defaults.set("keep", forKey: "rules.v1")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.path)
        let store = AppDataStore(domain: domain, defaults: defaults, directories: [owned])
        #expect(throws: (any Error).self) { try store.erase() }
        #expect(defaults.string(forKey: "rules.v1") == "keep")
    }
}
