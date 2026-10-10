import SwiftUI
import Foundation

/// 读取随包许可证，提供可滚动、可选择的完整文本。
struct LicenseView: View {
    private let licenseText: String = {
        guard let url = Bundle.main.url(forResource: "LICENSE", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "许可证文本读取失败。"
        }
        return text
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("GNU GENERAL PUBLIC LICENSE").font(.headline)
                Text("GPL-3.0-only").font(.caption).foregroundStyle(.secondary)
            }.padding(20)
            Divider()
            ScrollView {
                Text(verbatim: licenseText)
                    .accessibilityIdentifier("license-text")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
        }
    }
}

#Preview("许可证") {
    LicenseView().frame(width: 680, height: 600)
}
