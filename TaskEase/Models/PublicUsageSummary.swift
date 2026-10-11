import Foundation

/// 公开看板的近三十日活跃安装估计；不表示实时在线人数。
struct PublicUsageSummary: Equatable, Sendable {
    let activeInstallations: Int
    let updatedAt: Date?
}
