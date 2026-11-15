import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 设置中的“自动化”分组：规则模板导入导出，以及 URL Scheme 与快捷指令说明。
struct AutomationSettingsSection: View {
    @Bindable var model: AppModel
    @State private var message: String?

    var body: some View {
        Section("automation.section") {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Button("template.import") { importRules() }.accessibilityIdentifier("import-rules")
                    Button("template.export") { exportRules() }.disabled(model.rules.isEmpty)
                        .accessibilityIdentifier("export-rules")
                }
                Text("template.note").font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("automation.shortcuts").fixedSize(horizontal: false, vertical: true)
                Text("automation.url").fixedSize(horizontal: false, vertical: true)
                Text(verbatim: Self.examples).font(.caption.monospaced()).textSelection(.enabled)
                    .foregroundStyle(.secondary)
            }.font(.callout)
        }
        .alert("automation.section", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("common.ok", role: .cancel) { message = nil }
        } message: { Text(message ?? "") }
    }

    private static let examples = """
    taskease://toggle
    taskease://pause?app=com.example.app&minutes=60
    taskease://resume?app=com.example.app
    """

    private func exportRules() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "TaskEase-rules.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.exportRules().write(to: url, options: .atomic)
            message = String(localized: "template.exported \(model.rules.count)")
        } catch { message = error.localizedDescription }
    }

    private func importRules() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            // 模板只是几 KB 的 JSON，过大的文件直接拒绝。
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 1_048_576 else { throw RuleTemplate.Failure.unreadable }
            let result = try model.importRules(Data(contentsOf: url))
            message = result.skipped.isEmpty ? String(localized: "template.imported \(result.rules.count)")
                : String(localized: "template.importedSkipped \(result.rules.count) \(result.skipped.count)")
        } catch { message = error.localizedDescription }
    }
}
