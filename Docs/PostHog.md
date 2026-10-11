# PostHog 使用统计

## 项目配置

TaskEase 使用 PostHog US Cloud 的 Product Analytics，项目 ID 为 657959。项目已完成安装核验，选择 Free 计划，界面显示每月 100 万事件额度与 1 年数据保留期。

接收域名为 https://us.i.posthog.com，应用调用 /i/v0/e/ Capture API。项目配置保存在 TaskEase/Resources/PostHog.json，随应用包提供。

projectToken 是 PostHog 标注可在公开应用中使用的项目令牌，本应用用它写入事件，无法凭它读取后台分析数据。源码派生项目应配置自己的 PostHog 项目。管理后台和查询 API 的私人密钥只供维护者在服务端使用，不写入应用配置。

## 用户设置与数据

“设置 → 使用统计 → 分享匿名使用统计”默认关闭。用户开启后生成随机安装 UUID，用于对参与统计的安装进行跨天去重。不开启时不创建标识、发送任务、统计计时器或网络观察器。

应用每天发送 taskease daily active 事件，包含以下字段：

| 字段 | 含义 |
| --- | --- |
| distinct_id | 本地生成的随机安装 UUID |
| uuid | 此次每日事件的 UUID，重试保持不变 |
| timestamp | UTC 时间戳，重试保持不变 |
| app_version、app_build | TaskEase 版本与构建号 |
| os_name、os_version | macOS 名称与系统版本 |
| region | 系统配置的地区代码 |
| local_day | 本机时区下的日期 |
| is_test | 样例核验标记，正常上报为 false |

事件设置 $process_person_profile=false，不建立用户资料；设置 $geoip_disable=true 与 $ip=0.0.0.0，关闭事件 IP 地区补充。网络连接本身会让接收服务看到请求来源，服务的运行日志按其政策处理。

应用不采集用户姓名、邮箱、硬件序列号、应用列表、进程信息、文件路径、后台规则或通信内容。系统地区是地区设置，不是实际定位。随机 ID 属于去标识化安装统计，不能精确代表物理电脑或人数。

## 调度与失败处理

使用本机时区的公历，在当地中午 12 点安排一次性计时，允许约一分钟的系统调度余量。当天中午后启动、唤醒、恢复网络或改变时区时检查当天是否已成功发送；成功后等待下一天。

应用退出或电脑睡眠时不额外启动后台服务，也不唤醒电脑。未运行的历史日期不补发。电脑休眠、网络断开和系统调度可能延迟上报。

每日事件先持久化再发送，失败后至少等待 30 分钟，同一个本地日期最多尝试三次。重试使用相同事件 UUID、distinct_id、时间戳和属性，供 PostHog 去重。去重在服务端最终完成，短时间内可能出现重复。

HTTP 请求通过临时 URLSession 发送，有请求和资源超时，不跟随重定向。2xx 表示接收端接受请求，是否已进入分析表以后台 Activity 为准。失败只影响统计，不改变 CPU 和网络规则。

关闭开关、应用退出和清理数据时取消任务、计时器与观察器。取消后的回调通过代次检查停止写入。统计同意开关保存在 usageAnalytics.enabled，随机标识和待发送记录保存在 usageAnalytics.v1，位于本应用 UserDefaults 偏好域。

“清除数据并退出…”同时清理这些本地记录。已经发送到 PostHog 的事件遵循服务端保留期限；清理本地数据不会删除服务端历史。关闭后再次开启继续使用原安装标识，避免重复计算安装数。

## 后台查看

已配置 [TaskEase 使用统计看板](https://us.posthog.com/project/657959/dashboard/2196112)，其中 [30 天活跃安装与环境分布](https://us.posthog.com/project/657959/insights/MfmaDUaP) 采用 SQL 聚合。查询源文件为 [posthog-active-installations.sql](../Scripts/posthog-active-installations.sql)，按事件的 distinct_id 去重，直接计算匿名事件。

Activity 中可以查看 taskease daily active 的接收记录与属性。正式统计必须筛选 is_test=false。安装核验事件设置 is_test=true，系统地区为 example，仅用于证明真实应用客户端与接收项目已接通。

创建 Trends 时选择 taskease daily active，聚合选择 Unique users，即去重的随机安装标识。过去 30 天的累计去重数是参与统计的活跃安装估计值。按 app_version、os_version 或 region 分组可查看对应分布，同一安装可能出现在多个版本分组中，因此不能把这些分组简单相加作为整体安装量。

该事件每天最多成功一次，适合活跃安装与环境分布；不提供在线状态、页面访问次数或使用时长。默认关闭、离线与自行修改客户端都会影响覆盖范围。

## 验证与维护

自动验证使用固定日期、隔离偏好域和模拟发送器，覆盖中午调度、夏令时、时钟回退、每日去重、重试上限、请求字段、同意开关与清理取消。Debug 构建、测试及 SwiftUI 预览使用夹具模式，即使切换同意开关也不会自动发送数据；用户的统计同意状态只由 Release 构建读取和保存。

本机真实接入核验使用：

```sh
sh Scripts/build-app.sh
build/TaskEase.app/Contents/MacOS/TaskEase --analytics-check
```

该命令显式发送一条带 is_test=true 的合成事件，不读取用户配置。控制台接受结果应与 PostHog Activity 的实际接收记录共同核对。自动测试不调用此命令。

修改接收配置后重新构建，检查应用包中的 PostHog.json。更换项目令牌时发布新版本，旧应用仍持有旧令牌。无需为应用创建个人 API 密钥。

参考 [PostHog Capture API](https://posthog.com/docs/api/capture)、[匿名事件与用户资料](https://posthog.com/docs/data/anonymous-vs-identified-events)、[事件去重](https://posthog.com/docs/data/events)。
