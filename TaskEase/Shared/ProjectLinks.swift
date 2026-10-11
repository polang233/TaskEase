import Foundation

/// 公共项目链接集中维护，反馈与统计入口始终指向项目自己的页面。
enum ProjectLinks {
    static let repository = URL(string: "https://github.com/polang233/TaskEase")!
    static let issues = repository.appendingPathComponent("issues")
    static let statistics = URL(string: "https://us.posthog.com/shared/Do9W3574hr41SnipsKsuPGuWM_LYrw")!
}
