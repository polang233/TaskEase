import Foundation
import Observation

/// 只在用户点击时检查一次 GitHub 最新发布；没有后台定时检查。
@MainActor @Observable
final class UpdateChecker {
    enum State: Equatable {
        case idle, checking, upToDate, noRelease, failed(String)
        case available(version: String, url: URL)
    }

    private(set) var state: State = .idle
    @ObservationIgnored private let fixtures: Bool
    @ObservationIgnored private var task: Task<Void, Never>?

    init(fixtures: Bool = false) { self.fixtures = fixtures }

    func check() {
        guard task == nil else { return }
        if fixtures { state = .upToDate; return }
        state = .checking
        task = Task { [weak self] in
            let result: State
            do {
                if let release = try await GitHubClient.shared.latestRelease() {
                    result = VersionOrder.isNewer(release.version, than: AppVersion.short)
                        ? .available(version: release.version, url: release.htmlURL) : .upToDate
                } else {
                    result = .noRelease
                }
            } catch GitHubClient.Failure.rateLimited {
                result = .failed("GitHub 请求过于频繁，请稍后再试。")
            } catch is CancellationError {
                return
            } catch {
                result = .failed("暂时无法连接 GitHub。")
            }
            guard let self, !Task.isCancelled else { return }
            self.state = result
            self.task = nil
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        if state == .checking { state = .idle }
    }
}
