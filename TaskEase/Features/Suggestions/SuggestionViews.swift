import SwiftUI

/// 管理窗口顶部的建议提示条：有建议时出现，关掉后只在出现新建议时再次显示。
struct SuggestionBanner: View {
    @Bindable var model: AppModel
    @State private var showsList = false

    var body: some View {
        let suggestions = model.suggestions
        let ids = Set(suggestions.map(\.id))
        if !suggestions.isEmpty && (!ids.isSubset(of: model.suggestionCenter.settings.bannerHiddenFor) || showsList) {
            HStack(spacing: 10) {
                Image(systemName: "lightbulb.max").foregroundStyle(.yellow).font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("suggestion.banner.title \(suggestions.count)").font(.callout.weight(.semibold))
                    Text(suggestions.prefix(3).map(\.name).formatted(.list(type: .and)))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button("suggestion.banner.show") { showsList = true }
                    .popover(isPresented: $showsList, arrowEdge: .bottom) {
                        SuggestionList(model: model).frame(width: 440)
                    }
                    .accessibilityIdentifier("show-suggestions")
                Button("suggestion.banner.hide", systemImage: "xmark") {
                    model.suggestionCenter.hideBanner(for: ids)
                }
                .labelStyle(.iconOnly).buttonStyle(.borderless).foregroundStyle(.secondary)
                .help("suggestion.banner.hide").pointingHand()
                .accessibilityIdentifier("hide-suggestions")
            }
            .padding(.horizontal, 16).padding(.vertical, 9)
            .background(Color.yellow.opacity(0.08))
            .overlay(alignment: .bottom) { Divider() }
        }
    }
}

/// 建议列表：每条显示后台平均占用、推荐方式与理由，可套用或忽略；底部调整阈值。
struct SuggestionList: View {
    @Bindable var model: AppModel

    var body: some View {
        let suggestions = model.suggestions
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("suggestion.list.title").font(.headline)
                Text("suggestion.list.note").font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if suggestions.isEmpty {
                Text("suggestion.list.empty").font(.callout).foregroundStyle(.secondary)
            } else if suggestions.count <= 3 {
                VStack(spacing: 8) { ForEach(suggestions) { row($0) } }
            } else {
                ScrollView {
                    VStack(spacing: 8) { ForEach(suggestions) { row($0) } }
                }.frame(height: 320)
            }
            Divider()
            HStack(spacing: 12) {
                Picker("suggestion.threshold.cpu", selection: Binding(get: { model.suggestionCenter.settings.cpuThreshold },
                    set: { value in model.suggestionCenter.update { $0.cpuThreshold = value } })) {
                    ForEach(SuggestionSettings.cpuChoices, id: \.self) { Text(verbatim: "\(Int($0))%").tag($0) }
                }.fixedSize()
                Picker("suggestion.threshold.gpu", selection: Binding(get: { model.suggestionCenter.settings.gpuThreshold },
                    set: { value in model.suggestionCenter.update { $0.gpuThreshold = value } })) {
                    ForEach(SuggestionSettings.gpuChoices, id: \.self) { Text(verbatim: "\(Int($0))%").tag($0) }
                }.fixedSize()
                Spacer()
                let dismissed = model.suggestionCenter.settings.dismissed.count
                if dismissed > 0 {
                    Button("suggestion.restore \(dismissed)") { model.suggestionCenter.restoreDismissed() }
                        .buttonStyle(.link).pointingHand()
                }
            }.font(.caption).controlSize(.small)
        }.padding(16)
    }

    private func row(_ suggestion: Suggestion) -> some View {
        HStack(alignment: .top, spacing: 10) {
            AppIcon(app: model.reportApplication(id: suggestion.id, name: suggestion.name), size: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(suggestion.name).lineLimit(1)
                Text(usage(suggestion)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                HStack(spacing: 4) {
                    Text("suggestion.recommend \(suggestion.method.title)").font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                    Text(verbatim: "·").foregroundStyle(.secondary)
                    Text(suggestion.kind.reason).font(.caption).foregroundStyle(.secondary)
                }.lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Button("suggestion.apply") { model.applySuggestion(suggestion) }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    .accessibilityIdentifier("apply-suggestion-\(suggestion.id)")
                Button("suggestion.dismiss") { model.suggestionCenter.dismiss(suggestion.id) }
                    .buttonStyle(.borderless).controlSize(.small).foregroundStyle(.secondary).pointingHand()
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func usage(_ suggestion: Suggestion) -> String {
        let cpu = Display.percent(suggestion.cpuPercent)
        guard let gpu = suggestion.gpuPercent else { return String(localized: "suggestion.usage.cpu \(cpu)") }
        if suggestion.compositingPercent >= SuggestionEngine.compositingFloor {
            return String(localized: "suggestion.usage.compositing \(cpu) \(Display.percent(gpu)) \(Display.percent(suggestion.compositingPercent))")
        }
        return String(localized: "suggestion.usage.gpu \(cpu) \(Display.percent(gpu))")
    }
}

#Preview("智能建议") {
    SuggestionList(model: AppModel(preview: true)).frame(width: 440)
}
