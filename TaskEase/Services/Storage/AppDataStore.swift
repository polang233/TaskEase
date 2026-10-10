import Foundation

/// 管理本应用的持久数据；清理前由调用者停止采样并恢复受控进程。
struct AppDataStore {
    let domain: String
    let defaults: UserDefaults
    let directories: [URL]

    static var current: AppDataStore {
        let domain = Bundle.main.bundleIdentifier ?? "com.github.polang233.TaskEase"
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        let directories = ["Application Support", "Caches", "Logs"].map {
            library.appendingPathComponent($0, isDirectory: true).appendingPathComponent(domain, isDirectory: true)
        } + [library.appendingPathComponent("Saved Application State", isDirectory: true)
            .appendingPathComponent(domain + ".savedState", isDirectory: true)]
        return AppDataStore(domain: domain, defaults: .standard, directories: directories)
    }

    /// 只删除显式归属本应用的目录与偏好域。失败向上传递，让用户可以重试。
    func erase() throws {
        for directory in directories where FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        defaults.removePersistentDomain(forName: domain)
        // 清理退出需要将偏好删除写回磁盘，避免进程结束前仍留下旧配置。
        guard defaults.synchronize() else { throw CocoaError(.fileWriteUnknown) }
    }
}
