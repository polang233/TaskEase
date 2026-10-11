# 数据管理与使用统计

## 本地数据

轻程的 CPU 规则、网络规则、显示设置和统计偏好由 UserDefaults 保存，控制归属日志单独保存在 Application Support。使用统计默认开启，可在“关于轻程 → 使用统计”中关闭，数据发送到 PostHog。

| 数据 | 位置 |
| --- | --- |
| 规则、应用名称与路径、显示偏好、窗口位置、统计同意与随机安装标识 | ~/Library/Preferences/com.github.polang233.TaskEase.plist |
| 进程恢复记录与工作进程锁 | ~/Library/Application Support/com.github.polang233.TaskEase/ |
| 应用缓存与日志 | ~/Library/Caches/com.github.polang233.TaskEase/、~/Library/Logs/com.github.polang233.TaskEase/ |
| 系统保存的窗口状态 | ~/Library/Saved Application State/com.github.polang233.TaskEase.savedState/ |

后两项只在存在时清理。单实例协调锁位于系统管理的用户临时目录，独立于持久数据。持锁期间保留同一个文件，避免清理数据时出现两个实例。

设置中的“清除数据并退出…”需要确认。确认后先停止事件和采样，等待控制进程退出并恢复受控进程，再删除本应用的数据及偏好域，最后退出。窗口自动保存会在清理前关闭。清理失败时显示错误，用户可重试或退出。

删除 .app 与删除用户数据是两个操作。普通应用把可修改的数据存放在用户 Library，应用包存放代码和资源。小型设置通常用 UserDefaults，结构化记录可用 SwiftData、Core Data 或 SQLite，文件和缓存按用途存放。沙箱应用通常把数据写到容器中。

macOS 的应用移除并不保证清除应用生成的全部文件。应用自带卸载器或第三方清理工具可以识别和移除关联数据。轻程提供自己的数据清理入口，用户完成清理后再把应用移到废纸篓。

参考 [Apple 应用删除说明](https://support.apple.com/en-gb/102610)、[UserDefaults](https://developer.apple.com/documentation/foundation/userdefaults) 和 [Application Support 目录](https://developer.apple.com/documentation/foundation/url/applicationsupportdirectory)。

## 使用统计

使用统计接入 PostHog Product Analytics，默认开启，可在“关于轻程 → 使用统计”中关闭。在启动及运行期间低频发送环境与本应用的配置概况，用随机安装标识去重。调度、关闭、清理范围和后台查看方法见 [PostHog 文档](PostHog.md)。

新增的全局内存、网速与温度只用于本机概览，不增加统计上报字段。公开设备数仅在打开统计窗口或点击刷新时读取，缓存保存在内存中。
