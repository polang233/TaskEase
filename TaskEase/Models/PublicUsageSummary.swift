import Foundation

/// 公开看板的近三十日活跃安装估计；不表示实时在线人数。
struct PublicUsageSummary: Equatable, Sendable {
    struct Day: Equatable, Sendable {
        let date: Date
        let installations: Int
    }

    struct Region: Equatable, Sendable {
        let name: String
        let installations: Int
    }

    let activeInstallations: Int
    let updatedAt: Date?
    /// 每日去重活跃安装，按 UTC 日期；看板缺少该卡片时为空。
    var days: [Day] = []
    /// 按安装数降序，最多保留五个地区。
    var regions: [Region] = []
}
