import AppKit
import Foundation
import Observation

/// 检查 GitHub 最新发布并执行一键更新。启动时自动检查一次，之后只在用户点击时检查；没有周期定时器。
/// 发现新版本时只在页眉和菜单栏显示提示，不主动弹出窗口。
@MainActor @Observable
final class UpdateChecker {
    enum Phase: Equatable {
        case idle, checking, upToDate, noRelease, failed(String)
        /// downloading 的进度为 nil 时表示还在连接，尚未收到数据。
        case available, downloading(Double?), installing, installFailed(String)
    }

    private(set) var phase: Phase = .idle
    /// 比当前版本新的发布；没有新版本时为 nil。
    private(set) var release: GitHubClient.Release?
    /// 用户选择跳过的版本；跳过后该版本不再显示提示，仍可在关于窗口手动查看。
    private(set) var skippedVersion: String?
    @ObservationIgnored private let fixtures: Bool
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var task: Task<Void, Never>?
    private static let skippedKey = "updates.skippedVersion"

    init(fixtures: Bool = false, defaults: UserDefaults = .standard) {
        self.fixtures = fixtures
        self.defaults = defaults
        skippedVersion = fixtures ? nil : defaults.string(forKey: Self.skippedKey)
    }

    var isBusy: Bool {
        switch phase {
        case .checking, .downloading, .installing: true
        default: false
        }
    }

    /// 发现新版本后在界面上保留入口，直到用户更新或退出。
    var hasUpdate: Bool { release != nil }

    /// 页眉与菜单栏的新版本提示：有新版本且没有被跳过。
    var showsBadge: Bool { release.map { $0.version != skippedVersion } ?? false }

    /// 一键更新需要发布页带有可校验的安装镜像，且当前应用所在位置可写。
    var canInstall: Bool { release?.diskImage != nil && UpdateInstaller.canReplaceInPlace }

    /// `automatic` 为启动检查：失败时保留原状态，不显示错误。
    func check(automatic: Bool = false) {
        guard task == nil, !isBusy else { return }
        if fixtures { phase = .upToDate; return }
        let previous = phase
        phase = .checking
        task = Task { [weak self] in
            let next: Phase
            var found: GitHubClient.Release?
            do {
                if let latest = try await GitHubClient.shared.latestRelease() {
                    if VersionOrder.isNewer(latest.version, than: AppVersion.short) {
                        found = latest
                        next = .available
                    } else {
                        next = .upToDate
                    }
                } else {
                    next = .noRelease
                }
            } catch GitHubClient.Failure.rateLimited {
                next = automatic ? previous : .failed(String(localized: "update.rateLimited"))
            } catch is CancellationError {
                return
            } catch {
                next = automatic ? previous : .failed(String(localized: "update.offline"))
            }
            guard let self, !Task.isCancelled else { return }
            self.task = nil
            self.release = found
            self.phase = next
        }
    }

    /// 下载并暂存新版本，成功后安排替换并退出；不能原地替换时打开发布页。
    func install() {
        guard let release, task == nil else { return }
        guard canInstall else { NSWorkspace.shared.open(release.htmlURL); return }
        phase = .downloading(nil)
        let report: @Sendable (Double) -> Void = { value in
            Task { @MainActor in self.reportProgress(value) }
        }
        task = Task { [weak self] in
            do {
                let staged = try await UpdateInstaller.prepare(release, progress: report)
                guard let self, !Task.isCancelled else { UpdateInstaller.discard(staged); return }
                self.phase = .installing
                guard UpdateInstaller.scheduleReplacement(staged) else {
                    UpdateInstaller.discard(staged)
                    self.finishInstall(.installFailed(UpdateInstaller.Failure.copy.message))
                    return
                }
                // 正常退出流程会先恢复被限制的进程，再由脚本替换应用。
                NSApp.terminate(nil)
            } catch is CancellationError {
                self?.finishInstall(.available)
            } catch let failure as UpdateInstaller.Failure {
                self?.finishInstall(.installFailed(failure.message))
            } catch {
                self?.finishInstall(.installFailed(UpdateInstaller.Failure.download.message))
            }
        }
    }

    /// 仅预览与测试使用，正常运行时忽略。
    func showPreview(_ release: GitHubClient.Release) {
        guard fixtures else { return }
        self.release = release
        phase = .available
    }

    func skipCurrentRelease() {
        guard let release else { return }
        skippedVersion = release.version
        if !fixtures { defaults.set(release.version, forKey: Self.skippedKey) }
    }

    func cancel() {
        task?.cancel()
        task = nil
        switch phase {
        case .checking: phase = .idle
        case .downloading: phase = release == nil ? .idle : .available
        default: break
        }
    }

    private func reportProgress(_ value: Double) {
        if case .downloading = phase { phase = .downloading(value) }
    }

    private func finishInstall(_ next: Phase) {
        task = nil
        phase = next
    }
}
