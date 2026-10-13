import Foundation
import CryptoKit

/// 一键更新：下载发布页的安装镜像，校验摘要，挂载后核对应用标识、版本与签名，再放到当前应用旁边。
/// 替换由应用退出后的脚本完成：旧版先改名备份，新版就位后删除备份，失败则还原，最后重新打开。
enum UpdateInstaller {
    enum Failure: Error {
        case download, checksum, package, copy

        var message: String {
            switch self {
            case .download: String(localized: "update.error.download")
            case .checksum: String(localized: "update.error.checksum")
            case .package: String(localized: "update.error.package")
            case .copy: String(localized: "update.error.copy")
            }
        }
    }

    /// 已暂存的新版本与要替换的当前应用，位于同一目录，替换时只需改名。
    struct Staged: Sendable {
        let app: URL
        let target: URL
    }

    /// 当前应用能否原地替换：在 DMG、App Translocation 隔离目录或不可写目录中运行时不能。
    static var canReplaceInPlace: Bool {
        let target = Bundle.main.bundleURL.resolvingSymlinksInPath()
        let parent = target.deletingLastPathComponent().path
        return !target.path.contains("/AppTranslocation/")
            && FileManager.default.isWritableFile(atPath: parent)
            && FileManager.default.isWritableFile(atPath: target.path)
    }

    static func prepare(_ release: GitHubClient.Release,
                        progress: @escaping @Sendable (Double) -> Void) async throws -> Staged {
        guard let asset = release.diskImage, let expected = asset.sha256 else { throw Failure.package }
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("TaskEaseUpdate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        let image = work.appendingPathComponent("update.dmg")
        do { try await Download.file(from: asset.downloadURL, to: image, expectedBytes: asset.size, progress: progress) }
        catch is CancellationError { throw CancellationError() }
        catch { throw Failure.download }
        try Task.checkCancellation()
        guard try sha256(of: image) == expected else { throw Failure.checksum }

        return try await Task.detached(priority: .utility) {
            try stage(image: image, version: release.version, work: work)
        }.value
    }

    /// 挂载只读镜像，核对后用 ditto 复制到当前应用所在目录的隐藏位置。
    private static func stage(image: URL, version: String, work: URL) throws -> Staged {
        let mount = work.appendingPathComponent("mount", isDirectory: true)
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        guard run("/usr/bin/hdiutil", ["attach", image.path, "-nobrowse", "-readonly", "-noautoopen",
                                       "-noverify", "-mountpoint", mount.path]) else { throw Failure.package }
        defer { _ = run("/usr/bin/hdiutil", ["detach", mount.path, "-quiet", "-force"]) }

        let candidates = (try? FileManager.default.contentsOfDirectory(at: mount, includingPropertiesForKeys: nil)) ?? []
        guard let app = candidates.first(where: { url in
            guard url.pathExtension == "app", let bundle = Bundle(url: url) else { return false }
            return bundle.bundleIdentifier == Bundle.main.bundleIdentifier
                && bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == version
        }), run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path]) else { throw Failure.package }

        let target = Bundle.main.bundleURL.resolvingSymlinksInPath()
        let staged = target.deletingLastPathComponent().appendingPathComponent(".TaskEase-\(version)-update.app")
        try? FileManager.default.removeItem(at: staged)
        guard run("/usr/bin/ditto", [app.path, staged.path]) else {
            try? FileManager.default.removeItem(at: staged)
            throw Failure.copy
        }
        return Staged(app: staged, target: target)
    }

    /// 启动替换脚本后由调用方退出应用；脚本等本进程结束再改名，避免替换正在运行的程序。
    static func scheduleReplacement(_ staged: Staged) -> Bool {
        let script = """
        while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
        backup="$3.previous"
        rm -rf "$backup"
        if mv "$3" "$backup"; then
            if mv "$2" "$3"; then rm -rf "$backup"; else mv "$backup" "$3"; fi
        fi
        rm -rf "$2"
        /usr/bin/open "$3"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "taskease-update", String(getpid()), staged.app.path, staged.target.path]
        do { try process.run(); return true } catch { return false }
    }

    static func discard(_ staged: Staged) {
        try? FileManager.default.removeItem(at: staged.app)
    }

    private static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    @discardableResult
    private static func run(_ tool: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}

/// 带进度的单文件下载；下载期间只持有一个临时会话，完成或取消后释放。
private final class Download: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let expectedBytes: Int
    private let progress: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var moveError: Error?

    private init(destination: URL, expectedBytes: Int, progress: @escaping @Sendable (Double) -> Void) {
        self.destination = destination
        self.expectedBytes = expectedBytes
        self.progress = progress
    }

    static func file(from url: URL, to destination: URL, expectedBytes: Int,
                     progress: @escaping @Sendable (Double) -> Void) async throws {
        let download = Download(destination: destination, expectedBytes: expectedBytes, progress: progress)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 600
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: download, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let task = session.downloadTask(with: url)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                download.lock.withLock { download.continuation = continuation }
                task.resume()
            }
        } onCancel: { task.cancel() }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : Int64(expectedBytes)
        if total > 0 { progress(min(1, Double(totalBytesWritten) / Double(total))) }
    }

    /// 系统在回调返回后删除临时文件，必须在这里移走。
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        do {
            guard (200..<300).contains(status) else { throw URLError(.badServerResponse) }
            try FileManager.default.moveItem(at: location, to: destination)
        } catch { lock.withLock { moveError = error } }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Error>? in
            defer { self.continuation = nil }
            return self.continuation
        }
        if let error = error ?? lock.withLock({ moveError }) {
            continuation?.resume(throwing: (error as? URLError)?.code == .cancelled ? CancellationError() : error)
        } else {
            continuation?.resume()
        }
    }
}
