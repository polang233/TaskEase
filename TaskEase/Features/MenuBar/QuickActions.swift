import SwiftUI

/// 菜单栏面板每行右侧的临时操作：暂停一段时间、立即恢复或恢复按规则执行；临时状态显示期限。
struct QuickActions: View {
    @Bindable var model: AppModel
    let app: AppReading

    var body: some View {
        let action = model.temporaryActions[app.id]
        HStack(spacing: 6) {
            if let action {
                Text(caption(action)).font(.caption2).foregroundStyle(action.isPause ? Color.blue : Color.orange)
                    .lineLimit(1).fixedSize().monospacedDigit()
            }
            control(action)
        }
    }

    @ViewBuilder private func control(_ action: TemporaryAction?) -> some View {
        switch action {
        case .pause:
            iconButton("quick.resume", systemImage: "play.circle.fill", tint: .blue) { model.resumeNow(app.id) }
        case .release:
            iconButton("quick.restoreRule", systemImage: "arrow.uturn.backward.circle", tint: .orange) {
                model.clearTemporaryAction(app.id)
            }
        case nil:
            if Policy.shouldControl(app.status) {
                iconButton("quick.resumeRule", systemImage: "play.circle", tint: .secondary) { model.resumeNow(app.id) }
            } else if app.canControl && !app.isSystemApp {
                Menu {
                    ForEach(Self.durations, id: \.self) { minutes in
                        Button(Self.title(minutes)) { model.pauseTemporarily(app.id, minutes: minutes) }
                    }
                    Divider()
                    Text("quick.pause.note")
                } label: {
                    Image(systemName: "pause.circle")
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .foregroundStyle(.secondary).help("quick.pause").pointingHand()
                .accessibilityLabel("quick.pause")
            }
        }
    }

    private func iconButton(_ title: LocalizedStringKey, systemImage: String, tint: Color,
                            action: @escaping () -> Void) -> some View {
        Button(title, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly).buttonStyle(.borderless).foregroundStyle(tint)
            .help(title).pointingHand()
    }

    private func caption(_ action: TemporaryAction) -> String {
        let time = action.until.formatted(date: .omitted, time: .shortened)
        return action.isPause ? String(localized: "quick.pausedUntil \(time)") : String(localized: "quick.releasedUntil \(time)")
    }

    /// 占用最高的五个应用，再加上有临时操作的应用：暂停后占用回落，仍要能从面板立即恢复。
    static func rows(_ apps: [AppReading], sortedBy key: AppSortKey, temporary: [String: TemporaryAction]) -> [AppReading] {
        let sorted = AppModel.sorted(apps, by: key)
        let top = Array(sorted.prefix(5))
        let shown = Set(top.map(\.id))
        return top + sorted.filter { temporary[$0.id] != nil && !shown.contains($0.id) }
    }

    static let durations: [Double] = [15, 60, 240]

    static func title(_ minutes: Double) -> String {
        minutes >= 60 ? String(localized: "quick.pause.hours \(Int(minutes / 60))")
            : String(localized: "quick.pause.minutes \(Int(minutes))")
    }
}
