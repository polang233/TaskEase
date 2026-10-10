# TaskEase 设计

## 状态与执行职责

AppModel 在 MainActor 上持有规则、显示设置、前台状态和窗口状态。ProcessMonitor actor 持有累计采样计数与可执行路径缓存，负责 libproc 扫描。NativeWorker 是常规进程控制的唯一写入者；WorkerController 负责启动、计划发送和失联后的补偿。

工作区消息更新前台状态后，先从缓存生成恢复计划，再异步刷新指标。回到前台的应用无需等待一次完整进程扫描。界面只修改规则，不直接发送暂停信号。

控制进程通过同一应用可执行文件的独立模式启动，使用当前用户权限。应用目标采用非沙箱配置，不安装管理员服务。

## 文件与模块

工程使用与磁盘同步的文件夹组织源码，一个应用目标内按职责划分文件。

| 目录 | 职责 |
| --- | --- |
| App | 入口、单实例、AppModel、类型化工作区事件与窗口控制 |
| Features/Applications | 运行列表、已配置列表与管理窗口 |
| Features/Rules | 规则编辑、Policy 与原有规则格式读写 |
| Features/MenuBar | 菜单栏面板 |
| Features/Settings、Help、About | 显示设置、使用帮助、关于信息与许可证查看 |
| Models | 应用读数、规则、偏好、进程身份和控制消息 |
| Services/Monitoring | 采样 actor、计数差分和采样周期策略 |
| Services/ProcessControl | libproc、Mach、Darwin 桥接，控制与恢复 |
| Shared | 视图组件、图标缓存与数值格式 |
| Resources | Icon Composer 图标、图片资源与完整许可证 |
| Validation | 只读快照与自建负载自检 |

Apple 的文件夹组织及本地包说明见 [管理项目文件与文件夹](https://developer.apple.com/documentation/xcode/managing-files-and-folders-in-your-xcode-project) 和 [使用本地包组织代码](https://developer.apple.com/documentation/xcode/organizing-your-code-with-local-packages)。

## 规则保存与应用身份

rules.v1 继续保存 bundle identifier 到 AppRule 的映射，off、gentle、budget 原始值保持稳定。ruleApplications.v1 独立保存应用名称和 bundle 路径，用于展示未运行的已配置应用。preferences.v1 保存外观、系统应用筛选和显示刷新间隔。

关闭某个应用的限制保留编辑记录和参数；移除规则删除该记录。没有有效规则时主开关关闭且不可启用。现有规则损坏时保留原始数据备份并关闭限制。

ProcessIdentity 包含 PID、启动时间和 UID。控制操作验证完整身份和可执行路径所属应用。路径缓存只用于采样；控制进程每次实施操作仍验证当前可执行路径。PID 复用不能把旧控制计划作用于新进程。

同一应用的成员共享 CPU 上限。系统应用、其他用户进程和共享服务不加入可控组。

## 采样与事件

RunningApplication 在 MainActor 上把 NSRunningApplication 转换为 Sendable 值。ProcessMonitor actor 串行扫描，AppModel 合并扫描期间到达的刷新请求。

显示与控制采样各自保留计数基线。控制检查更新成员和状态，显示数值只在刷新到期时更新。

可见数据窗口采用用户选择的 1、2、5、10 秒间隔。窗口可见性读取 occlusionState，完全遮挡或最小化时停止显示采样。没有可见面板时只扫描启用规则的应用；GPU 驱动统计只在显示系统概览时读取，并保留 4 秒缓存。

SamplingPolicy 分别考虑显示间隔、2 秒控制检查和后台等待期限。下一次检查取最早期限，慢速显示更新不会让控制计划的 3 秒失联期限到期。没有显示或执行需求时，不设置周期定时器。

NSWorkspace 应用激活、隐藏、启动、退出、睡眠和唤醒使用类型化消息。窗口可见性使用 macOS 27 的类型化消息，观察回调按声明的 actor 执行。睡眠前结束控制进程，唤醒后重新采样。

## CPU 控制与恢复

CPU 累计时间和墙钟使用相同 Mach 时间单位。CPU 上限以单核时间计算；总增量超额时暂停成员，额度恢复后继续。允许短时超额，空闲额度有上限，避免累积无限突发额度。

高级模式采用 Darwin 背景调度。当前系统 getpriority(PRIO_DARWIN_PROCESS, otherPID) 可能返回调用者状态，因此通过公开 proc_taskinfo 的任务优先级识别已有后台状态。只解除由 TaskEase 添加的请求。

控制计划失联期限为 3 秒。标准输入 EOF、心跳到期、解析失败和退出均触发恢复。控制进程持有独占锁；恢复记录仅在控制归属改变时写入，记录完整进程身份及由本工具降低优先级或暂停的成员。

已有暂停的进程不接管。恢复时按 UID、PID 和启动时间确认归属，路径变化会阻止新增限制，但不妨碍解除之前施加的暂停。控制进程异常结束后，主应用按恢复记录补偿；重启时恢复已经失联的旧记录。

## 单实例与窗口

ApplicationSession 在规则模型创建前取得同用户实例锁。重复启动通知当前实例恢复管理窗口，然后退出新进程。文件描述符采用 close-on-exec，锁随进程结束释放。

管理、设置、帮助、关于和许可证窗口各自复用同一 NSWindow。有打开或最小化的应用窗口时采用 regular activation policy，关闭全部窗口后采用 accessory policy。菜单面板的可见状态单独参与采样决策。

许可证视图从应用包的 LICENSE.txt 读取完整 GNU GPLv3 文本，采用可选择和滚动的文本展示。仓库 LICENSE 与随包文本保持一致，SPDX 标识为 GPL-3.0-only。

预览和测试使用独立数据，不创建正常状态栏入口。菜单栏图片明确采用 18 点逻辑尺寸并提供 Retina 资源。正常使用包由 Scripts/build-app.sh 生成 Release 构建。
