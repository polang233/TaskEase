import Foundation

/// 应用列表搜索：同时匹配显示名、应用包里的英文名与文件名、标识符，并忽略繁简和大小写差异。
/// 显示名随界面语言和应用自带的本地化变化，只比较显示名会出现“有的能搜到繁体、有的必须英文”。
@MainActor
enum AppSearch {
    private static var cache: [String: String] = [:]

    /// 统一为简体、小写、无音标的比较形式；结果缓存，应用名称集合很小。
    static func fold(_ text: String) -> String {
        if let cached = cache[text] { return cached }
        let simplified = text.applyingTransform(StringTransform("Hant-Hans"), reverse: false) ?? text
        let folded = simplified.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        if cache.count > 2000 { cache.removeAll() }
        cache[text] = folded
        return folded
    }

    static func matches(_ query: String, name: String, aliases: [String], id: String) -> Bool {
        let target = fold(query)
        guard !target.isEmpty else { return true }
        return ([name, id] + aliases).contains { fold($0).contains(target) }
    }

    /// 应用包里与界面语言无关的名称：Info.plist 的包名与显示名、可执行文件名、文件夹名、访达显示名。
    /// 按包路径缓存，避免每次刷新重复读取。
    private static var aliasCache: [String: [String]] = [:]

    static func aliases(for bundleURL: URL, excluding name: String) -> [String] {
        let key = bundleURL.path
        let all: [String]
        if let cached = aliasCache[key] {
            all = cached
        } else {
            let info = Bundle(url: bundleURL)?.infoDictionary ?? [:]
            let found = [info["CFBundleName"], info["CFBundleDisplayName"], info["CFBundleExecutable"]]
                .compactMap { $0 as? String }
                + [bundleURL.deletingPathExtension().lastPathComponent,
                   FileManager.default.displayName(atPath: bundleURL.path)]
            var seen = Set<String>()
            all = found.filter { !$0.isEmpty && seen.insert($0).inserted }
            aliasCache[key] = all
        }
        return all.filter { $0 != name }
    }
}
