import SwiftUI
import AppKit

/// 新版本详情：版本、更新内容与一键更新进度。从页眉、菜单栏的新版本提示或关于窗口进入。
struct UpdateView: View {
    @Bindable var model: AppModel
    private var updates: UpdateChecker { model.updates }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().scaledToFit()
                    .frame(width: 56, height: 56).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    if let release = updates.release {
                        Text("update.prompt.title \(release.version)").font(.title3.weight(.semibold))
                    } else {
                        Text("update.upToDate").font(.title3.weight(.semibold))
                    }
                    Text("update.prompt.current \(AppVersion.short)").font(.callout).foregroundStyle(.secondary)
                }
            }
            if let notes = updates.release.map(Self.notes), !notes.characters.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("update.notes").font(.headline)
                    ScrollView {
                        Text(notes).font(.callout).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(10)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            status
            HStack {
                if updates.release != nil && !updates.isBusy {
                    Button("update.skip") {
                        updates.skipCurrentRelease()
                        model.closeUtility(.update)
                    }.pointingHand()
                }
                Spacer()
                Button("update.later") { model.closeUtility(.update) }
                    .keyboardShortcut(.cancelAction).disabled(updates.phase == .installing).pointingHand()
                if let release = updates.release {
                    if updates.canInstall {
                        Button("update.install") { updates.install() }
                            .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                            .disabled(updates.isBusy).pointingHand()
                            .accessibilityIdentifier("install-update")
                    } else {
                        Link("update.download", destination: release.htmlURL)
                            .buttonStyle(.borderedProminent).pointingHand()
                    }
                }
            }
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private var status: some View {
        switch updates.phase {
        case .downloading(let value?):
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: value)
                Text("update.downloading \(Int((value * 100).rounded()))").font(.caption).foregroundStyle(.secondary)
            }
        case .downloading(nil):
            VStack(alignment: .leading, spacing: 6) {
                ProgressView().progressViewStyle(.linear)
                Text("update.connecting").font(.caption).foregroundStyle(.secondary)
            }
        case .installing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("update.installing").font(.caption).foregroundStyle(.secondary)
            }
        case .installFailed(let message):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                Text(message).font(.caption)
                if let release = updates.release {
                    Link("update.download", destination: release.htmlURL).font(.caption).pointingHand()
                }
            }
        default:
            if updates.release != nil && !updates.canInstall {
                Text("update.manual.note").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// 发布说明只保留标题与列表，去掉安装说明和校验值；标题加粗，列表改为圆点。
    static func notes(_ release: GitHubClient.Release) -> AttributedString {
        var lines: [String] = []
        for raw in (release.body ?? "").components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") {
                let title = String(line.dropFirst(3))
                if ["安装", "安裝", "Install", "Installation"].contains(where: title.hasPrefix) { break }
                lines.append((lines.isEmpty ? "" : "\n") + "**\(title)**")
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                lines.append("• " + line.dropFirst(2))
            } else if !line.isEmpty && !line.uppercased().hasPrefix("SHA-256") {
                lines.append(line)
            }
        }
        let text = lines.joined(separator: "\n")
        return (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}
