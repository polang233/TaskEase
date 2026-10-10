# 数据管理与使用统计

## 本地数据

轻程的规则和显示设置由 UserDefaults 保存，控制归属日志单独保存在 Application Support。当前没有使用统计上报。

| 数据 | 位置 |
| --- | --- |
| 规则、应用名称与路径、显示偏好、窗口位置 | ~/Library/Preferences/com.github.polang233.TaskEase.plist |
| 进程恢复记录与工作进程锁 | ~/Library/Application Support/com.github.polang233.TaskEase/ |
| 应用缓存与日志 | ~/Library/Caches/com.github.polang233.TaskEase/、~/Library/Logs/com.github.polang233.TaskEase/ |
| 系统保存的窗口状态 | ~/Library/Saved Application State/com.github.polang233.TaskEase.savedState/ |

后两项只在存在时清理。单实例协调锁位于系统管理的用户临时目录，独立于持久数据。持锁期间保留同一个文件，避免清理数据时出现两个实例。

设置中的“清除数据并退出…”需要确认。确认后先停止事件和采样，等待控制进程退出并恢复受控进程，再删除本应用的数据及偏好域，最后退出。窗口自动保存会在清理前关闭。清理失败时显示错误，用户可重试或退出。

删除 .app 与删除用户数据是两个操作。普通应用把可修改的数据存放在用户 Library，应用包存放代码和资源。小型设置通常用 UserDefaults，结构化记录可用 SwiftData、Core Data 或 SQLite，文件和缓存按用途存放。沙箱应用通常把数据写到容器中。

macOS 的应用移除并不保证清除应用生成的全部文件。应用自带卸载器或第三方清理工具可以识别和移除关联数据。轻程提供自己的数据清理入口，用户完成清理后再把应用移到废纸篓。

参考 [Apple 应用删除说明](https://support.apple.com/en-gb/102610)、[UserDefaults](https://developer.apple.com/documentation/foundation/userdefaults) 和 [Application Support 目录](https://developer.apple.com/documentation/foundation/url/applicationsupportdirectory)。

## 使用统计方案

建议首先公开近 30 天活跃安装数。指标定义为最近 30 天内有有效上报的安装 ID 去重数。

| 方案 | 能回答的问题 | 应用开销 |
| --- | --- | --- |
| GitHub Release 下载量徽章 | 安装包被下载多少次 | 无应用上报 |
| 用户自愿开启的日活与 30 天活跃安装 | 有多少安装近期运行过应用 | 运行时每天最多一次 HTTPS 请求 |
| 在线安装数 | 有多少安装最近发送过心跳 | 需要更频繁的联网和唤醒 |

GitHub 的下载量与仓库访问量表示相应平台活动，不能直接换算为正在使用的电脑数量。Release API 提供 download_count，Traffic API 提供仓库访问与克隆统计。

建议的上报流程：

1. 设置中提供使用统计开关，说明上报内容和公开指标，默认关闭。
2. 开启后在本地生成随机安装 ID，与本应用配置一同清理。
3. 应用启动或回到可见窗口时检查上次成功上报日期，每天最多一次。关闭应用或电脑睡眠时无需唤醒上报。
4. 上报安装 ID、应用版本和系统主版本。避免发送应用列表、规则、文件路径、序列号或硬件指纹。
5. HTTPS 服务按安装 ID 更新最后活跃时间，按服务端日期统计日活和 30 天活跃安装。验证请求、限制频率并避免日志长期保留 IP。
6. 公共接口仅返回汇总值。Shields.io 的 endpoint 徽章读取该接口，README 展示“30 天活跃安装”。

随机 ID 对应安装记录。清理数据或重新安装后可能产生新 ID；离线、自行关闭统计和修改客户端都会影响统计。该指标是参与上报的活跃安装估计值。

若要在线指标，可采用 10 分钟心跳和 20 分钟有效窗口。睡眠与联网中断会影响数值，需明确标注“近期在线安装”。对于强调低后台开销的轻程，日上报更合适。

统计服务、域名、数据保留期限和开关文案确定后再实现上报。公开汇总徽章不需要把管理令牌放进应用。

参考 [GitHub Release assets API](https://docs.github.com/en/rest/releases/assets)、[GitHub Traffic API](https://docs.github.com/en/rest/metrics/traffic) 和 [Shields endpoint badge](https://shields.io/badges/endpoint-badge)。
