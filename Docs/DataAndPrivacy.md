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

统计目标为活跃安装、应用版本、macOS 版本和系统地区的分布。建议通过用户自愿开启的每日上报实现，界面说明上报内容。

### 每日上报

按用户系统时区安排当地中午 12:00 的一次性计时。当天中午后启动应用、从睡眠唤醒或恢复网络时，检查并补发当天尚未成功的上报。成功后记录日期，当天不再发送。应用退出或电脑睡眠时无需额外后台服务，也不唤醒电脑。

系统时间、时区变化后重新计算下一次期限；服务端验证日期和限制频率。离线重试只在网络恢复或下次启动时触发，避免持续轮询。

上报内容可包含应用版本、macOS 版本、系统配置的地区代码和本地日期。系统地区表示用户的地区设置，与实际所在地可能不同。

要统计跨天去重的活跃安装，需要随机安装 ID，随应用配置清理。这属于去标识化统计。完全不带稳定标识时，可以统计上报次数和版本分布，但无法精确计算活跃安装数。

### 接收与展示

建议使用一个 HTTPS 接口和小数据库接收上报，例如 Cloudflare Workers 与 D1；小规模使用有免费额度。接口按安装 ID 和日期去重，保存有限期限的数据，仅提供汇总查询。收集器只保存所需字段，明确配置请求日志和数据保留策略。

GitHub 可以保存汇总 JSON，通过 README 徽章或 Pages 展示。GitHub Actions 可以定期读取汇总接口并更新展示文件。管理凭据放在服务端或 Actions Secrets。

GitHub Pages 提供静态托管。直接向仓库写入文件或触发 repository_dispatch 需要相应 GitHub 写入权限，因此匿名客户端的接收入口应与仓库写入权限分开。

建议的数据路径为：

`TaskEase 每日上报 → HTTPS 收集接口 → 汇总 JSON → GitHub README 徽章`

目前应用没有开启统计上报。收集服务与接收地址确定后，再接入每日调度和用户开关。

参考 [GitHub Pages](https://docs.github.com/en/pages/getting-started-with-github-pages/what-is-github-pages)、[repository_dispatch](https://docs.github.com/en/rest/repos/repos#create-a-repository-dispatch-event)、[Cloudflare Workers 额度](https://developers.cloudflare.com/workers/platform/pricing/) 和 [Cloudflare D1 额度](https://developers.cloudflare.com/d1/platform/pricing/)。
