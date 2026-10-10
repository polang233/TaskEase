import Foundation
import AppKit
import Darwin

/// 区分正常运行、测试和预览，隔离实例锁与界面入口。
enum LaunchContext: Equatable, Sendable {
    case application
    case validation(UUID)
    case uiTesting
    case preview
    case unitTesting

    static let current: LaunchContext = {
        do {
            return try parse(arguments: CommandLine.arguments, environment: ProcessInfo.processInfo.environment)
        } catch {
            fputs("TaskEase: invalid instance validation scope.\n", stderr)
            exit(64)
        }
    }()

    static func parse(arguments: [String], environment: [String: String]) throws -> LaunchContext {
        if let index = arguments.firstIndex(of: "--instance-test-scope") {
            guard arguments.indices.contains(index + 1), let scope = UUID(uuidString: arguments[index + 1]) else {
                throw CocoaError(.validationMissingMandatoryProperty)
            }
            return .validation(scope)
        }
        if arguments.contains("--ui-testing") { return .uiTesting }
        if environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" ||
            arguments.contains("-ApplePersistenceIgnoreStateQuietly") { return .preview }
        if environment["XCTestConfigurationFilePath"] != nil { return .unitTesting }
        return .application
    }

    var usesFixtures: Bool { self != .application }
    var hasStatusItem: Bool {
        switch self {
        case .application, .validation: return true
        case .uiTesting, .preview, .unitTesting: return false
        }
    }
    var opensManagement: Bool {
        switch self {
        case .application, .validation, .uiTesting: return true
        case .preview, .unitTesting: return false
        }
    }
    var coordinationDirectory: URL? {
        switch self {
        case .application:
            // 协调锁由系统临时目录管理，应用数据清理不会替换正在持有的锁文件。
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("com.github.polang233.TaskEase.session", isDirectory: true)
        case .validation(let scope):
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("TaskEase.Validation.\(scope.uuidString)", isDirectory: true)
        case .uiTesting, .preview, .unitTesting: return nil
        }
    }
}

/// 文件锁保持稳定 inode，持锁期间不替换或删除它。
final class ProcessFileLock {
    private let descriptor: Int32

    private init(descriptor: Int32) { self.descriptor = descriptor }

    static func acquire(at url: URL) throws -> ProcessFileLock? {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let descriptor = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        if flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            let failure = errno
            close(descriptor)
            if failure == EWOULDBLOCK || failure == EAGAIN { return nil }
            throw POSIXError(POSIXErrorCode(rawValue: failure) ?? .EIO)
        }
        return ProcessFileLock(descriptor: descriptor)
    }

    deinit { close(descriptor) }
}

private struct ApplicationOwner: Codable {
    let identity: ProcessIdentity
    let ready: Bool
}

/// 取得同用户实例锁，将重复启动请求转发给已经就绪的实例。
@MainActor
final class ApplicationSession: NSObject {
    static let shared = ApplicationSession(context: .current)
    private let context: LaunchContext
    private var lease: ProcessFileLock?
    private var identity: ProcessIdentity?
    private var onReopen: (() -> Void)?
    private var ownerURL: URL? { context.coordinationDirectory?.appendingPathComponent("application-owner.json") }
    private var notificationName: Notification.Name {
        Notification.Name("com.github.polang233.TaskEase.reopen")
    }

    init(context: LaunchContext) { self.context = context; super.init() }

    /// 返回 false 表示本次启动已交给已有实例处理。
    func claim() throws -> Bool {
        guard let directory = context.coordinationDirectory else { return true }
        if lease != nil { return true }
        let deadline = Date().addingTimeInterval(2)
        repeat {
            if let claimed = try ProcessFileLock.acquire(at: directory.appendingPathComponent("application.lock")) {
                guard let current = NativeProcess.identity(getpid()) else { throw CocoaError(.fileReadUnknown) }
                lease = claimed
                identity = current
                try publish(ready: false)
                return true
            }
            if notifyExistingApplicationIfReady() { return false }
            usleep(20_000)
        } while Date() < deadline
        return false
    }

    func startHandlingReopen(_ action: @escaping () -> Void) throws {
        guard lease != nil, let identity else { return }
        onReopen = action
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(receiveReopen), name: notificationName,
            object: String(identity.pid), suspensionBehavior: .deliverImmediately)
        try publish(ready: true)
    }

    @objc private func receiveReopen(_ notification: Notification) { onReopen?() }

    private func publish(ready: Bool) throws {
        guard let ownerURL, let identity else { return }
        try JSONEncoder().encode(ApplicationOwner(identity: identity, ready: ready))
            .write(to: ownerURL, options: .atomic)
    }

    private func notifyExistingApplicationIfReady() -> Bool {
        guard let ownerURL, let data = try? Data(contentsOf: ownerURL),
              let owner = try? JSONDecoder().decode(ApplicationOwner.self, from: data),
              owner.ready, owner.identity.uid == geteuid(), NativeProcess.isAlive(owner.identity),
              let running = NSRunningApplication(processIdentifier: owner.identity.pid),
              running.bundleIdentifier == Bundle.main.bundleIdentifier else { return false }
        running.activate(options: [])
        DistributedNotificationCenter.default().postNotificationName(
            notificationName, object: String(owner.identity.pid), userInfo: nil, deliverImmediately: true)
        return true
    }

    func finish() {
        DistributedNotificationCenter.default().removeObserver(self)
        if lease != nil, let ownerURL { try? FileManager.default.removeItem(at: ownerURL) }
        onReopen = nil
        identity = nil
        lease = nil
    }
}
