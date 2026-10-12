# 多语言与翻译

轻程使用 Xcode 的 String Catalog。开发语言为英文，界面文案用英文语义键引用，目前提供英文、简体中文和繁体中文。

## 文件

| 文件 | 内容 |
| --- | --- |
| `TaskEase/Resources/Localizable.xcstrings` | 全部界面文案，每个键带有给译者的说明 |
| `TaskEase/Resources/InfoPlist.xcstrings` | Finder、程序坞中显示的应用名称 |

键按界面区域分组，例如 `settings.theme`、`rule.timing.always`。带参数的键在末尾写出占位符，例如 `list.search %lld`；`%lld` 为整数，`%@` 为文本，多个参数可用 `%1$@`、`%2$@` 调整顺序。计数类英文文案使用单复数变体。

## 添加一种语言

1. 用 Xcode 打开 `Localizable.xcstrings`，点左下角“+”添加语言；`InfoPlist.xcstrings` 同样添加。
2. 逐条填写翻译，保持占位符数量一致，状态改为已翻译。没有 Xcode 时可直接编辑 JSON，结构与已有语言相同。
3. 在 `TaskEase/Models/AppLanguage.swift` 中加入该语言，名称用这种语言本身书写，例如 `日本語`。
4. 在工程设置的 Localizations 中加入该语言。

## 翻译约定

- 按 macOS 中该语言的习惯用词，例如“设置 / 設定 / Settings”“结束 / Quit”。语气简短、口语化，避免逐字直译。
- 繁体中文采用台湾 macOS 用语：App、記憶體、處理程序、前景／背景、說明、結束，引号用「」。
- 不翻译 CPU、GPU、GB、MB/s 等单位与缩写；数值格式由系统按地区处理。
- 应用名：英文为 TaskEase，简体中文为轻程，繁体中文为輕程。

## 预览与检查

在设置中选择语言，点“立即重新开启”后生效；也可以用命令行临时指定：

```sh
build/TaskEase.app/Contents/MacOS/TaskEase -AppleLanguages "(en)"
```

先运行 `sh Scripts/build-app.sh`，再按语言渲染界面预览，检查文字长度与换行：

```sh
PREVIEW_LANGUAGE=zh-Hant bash Scripts/render-previews.sh Artifacts/local/zh-Hant
```

统计页中的国家和地区名称来自公开看板数据，不经过应用翻译。

## 提交翻译

欢迎通过 Pull Request 提交新语言或改进现有翻译。请在说明中注明语言与地区，并附一两张关键界面的截图。
