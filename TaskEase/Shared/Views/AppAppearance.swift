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

import SwiftUI

extension ThemeMode {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
