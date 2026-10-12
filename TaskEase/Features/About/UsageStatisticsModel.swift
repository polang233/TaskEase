import Foundation
import Observation

/// 统计窗口请求由应用生命周期管理，关窗和退出会主动取消，不依赖视图是否被销毁。
@MainActor @Observable
final class UsageStatisticsModel {
    private(set) var summary: PublicUsageSummary?
    private(set) var loading = false
    private(set) var failed = false
    @ObservationIgnored private let fixtures: Bool
    @ObservationIgnored private let loader: @Sendable (Bool) async throws -> PublicUsageSummary
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    init(fixtures: Bool = false,
         loader: @escaping @Sendable (Bool) async throws -> PublicUsageSummary = { try await PublicUsageCache.shared.load(refresh: $0) }) {
        self.fixtures = fixtures
        self.loader = loader
        if fixtures {
            let today = Calendar.current.startOfDay(for: Date())
            let days = (0..<30).map { offset in
                PublicUsageSummary.Day(date: today.addingTimeInterval(Double(offset - 29) * 86_400),
                                       installations: [3, 4, 4, 5, 6, 5, 7][offset % 7] + offset / 6)
            }
            summary = .init(activeInstallations: 18, updatedAt: nil, days: days,
                            regions: [.init(name: "中国", installations: 12), .init(name: "美国", installations: 4),
                                      .init(name: "日本", installations: 2)])
        }
    }

    func refresh(force: Bool = false) {
        guard !fixtures, task == nil else { return }
        loading = true
        failed = false
        let requestGeneration = generation
        let loader = loader
        task = Task { [weak self] in
            do {
                let value = try await loader(force)
                guard !Task.isCancelled, let self, self.generation == requestGeneration else { return }
                self.summary = value
                self.loading = false
                self.task = nil
            } catch {
                guard !Task.isCancelled, let self, self.generation == requestGeneration else { return }
                self.failed = true
                self.loading = false
                self.task = nil
            }
        }
    }

    /// 取消后保留已显示数字，忽略迟到响应；下一次打开仍可使用内存缓存。
    func cancel() {
        generation += 1
        task?.cancel()
        task = nil
        loading = false
    }
}
