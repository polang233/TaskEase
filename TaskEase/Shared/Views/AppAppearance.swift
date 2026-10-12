import AppKit

/// 加载 18 点模板图标，让系统适配菜单栏颜色与 Retina 缩放。
@MainActor
enum MenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(resource: .taskEaseMenu)
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }()
}

enum AppVersion {
    static var short: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1" }
}

extension ThemeMode {
    /// 外观统一设在 NSApp 上：跟随系统时设为 nil，所有窗口、菜单栏面板和卡片同步切换。
    /// 视图级 preferredColorScheme 从深色改回 nil 时不会复位已设置的窗口外观，因此不再使用。
    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}
