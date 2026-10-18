# 02 架构

## 进程模型

```
┌──────────────────────────────┐   命名管道 JSON    ┌──────────────────────┐
│ taskease-core.exe（用户权限） │◄────────────────►│ 界面进程（按需启动）  │
│ 托盘·前台检测·采样·规则执行   │                   │ 管理窗口·托盘面板     │
│ 恢复记录·更新·统计·IPC 服务端 │                   └──────────────────────┘
└──────┬───────────────┬───────┘
       │ 句柄等待       │ 命名管道（可选）
┌──────▼────────────┐ ┌▼────────────────────────────────┐
│ taskease-core.exe │ │ taskease-svc.exe（LocalSystem）   │
│ --guard 守护模式   │ │ WFP 阻断·WinDivert 限速·ETW 采集  │
└───────────────────┘ └─────────────────────────────────┘
             帧率注入：te-fps-hook.dll 由核心注入目标进程，通过共享内存读取目标帧率
```

| 进程 | 生命周期 | 职责 |
| --- | --- | --- |
| core | 登录后常驻，单实例（命名互斥量 `Local\TaskEase.Core`） | 所有规则的唯一执行者；持有规则、偏好和前台状态 |
| guard | 只在存在受控进程时存在，由 core 启动 | 等待 core 的进程句柄；core 异常退出时按恢复记录恢复 |
| UI | 打开窗口或托盘面板时由 core 启动，全部窗口关闭后保活 2 分钟再退出 | 纯展示与编辑，不直接控制任何进程 |
| svc | 可选的 Windows 服务，按需启动 | 执行需要管理员权限的网络操作和 ETW 采集；只接受来自安装目录内 core 的请求 |

对应 macOS 版：core ≈ AppModel + ProcessMonitor + WorkerController；guard ≈ NativeWorker 的失联恢复；UI ≈ SwiftUI 视图。

## 线程与事件（core）

- **消息线程**：隐藏窗口加消息循环，负责托盘图标（`Shell_NotifyIconW`）、`SetWinEventHook`（前台、最小化）、`WTSRegisterSessionNotification`、`WM_QUERYENDSESSION`/`WM_ENDSESSION`、任务栏重建（`TaskbarCreated`）和主题变化（`WM_SETTINGCHANGE`）。
- **工作线程**：一个 tokio current-thread 运行时，负责采样调度、规则执行、IPC 和网络请求。
- 两个线程之间通过通道传递类型化事件（对应 macOS 的 `WorkspaceEvents`）。
- 不使用全局鼠标或键盘钩子，也不轮询前台窗口。

## 模块划分（crates）

| crate | 职责 | 能否在 macOS 上测试 |
| --- | --- | --- |
| te-model | `AppRule`（可组合的性能限制、后台音量、降低优先级，含旧版 `mode` 迁移）/`ControlMode`/`Policy`/`SamplingPolicy`/`BudgetCredit`/`NetworkRule`/`TokenBucket`/`FrameRule`，IPC 消息类型（serde），应用键规范化 | 能，`cargo test -p te-model` |
| te-sys | Windows API 的安全封装：进程快照、身份、令牌、Job、挂起、优先级、D3DKMT、窗口、图标、电源、托盘 | 只能 `cargo check --target x86_64-pc-windows-msvc`（V-14） |
| te-core | 二进制 `taskease-core.exe`：普通模式、`--guard`、`--self-check`、`--analytics-check` | 否 |
| te-service | 二进制 `taskease-svc.exe` | 否 |
| te-fps-hook | cdylib `te-fps-hook.dll` | 否 |

te-model 不能依赖 Windows API。纯逻辑都放在这里，并用 `Windows/fixtures/` 的 JSON 用例测试。

## 应用分组

Windows 没有 bundle，“应用”由 core 按下面的顺序推断：

1. **打包应用（MSIX/UWP）**：`GetPackageFamilyName` 成功，就按包族名归组。
2. **父子关系**：子进程的父进程属于某个应用，并且父进程的创建时间早于子进程（防止 PID 复用造成误判），子进程的映像路径也在该应用根目录内，就并入父进程所在的应用。
3. **安装根目录**：映像路径位于同一个应用根目录下的进程归为一组。应用根目录的取法：
   - `Program Files*\<厂商>\<产品>\...`：取到 `<产品>` 这一级；只有一级时取那一级。
   - `%LOCALAPPDATA%\Programs\<产品>\...`：取 `<产品>`。
   - Squirrel 安装器的版本目录（`%LOCALAPPDATA%\<产品>\app-1.2.3\`）：去掉版本目录，取上一级。
   - 其他情况取 exe 所在的目录。
4. **跨根目录的辅助进程**（如浏览器更新器）不归组，单独显示。

**主进程**：一组进程中有可见顶层窗口、并且创建时间最早的那个；没有窗口时取创建时间最早的。

**显示名称**：按以下优先级取：

1. 打包应用的 `DisplayName`。
2. 开始菜单快捷方式名称（扫描 `%ProgramData%` 和 `%APPDATA%` 下的 `Microsoft\Windows\Start Menu\Programs`，解析 `.lnk` 的目标路径，结果缓存）。
3. exe 版本信息里的 `FileDescription`。如果值是 `Electron`、`Chromium` 这类通用名，跳过这一项。
4. 去掉 `.exe` 后的文件名。

**图标**：

- 用 `IShellItemImageFactory::GetImage` 请求 256px 图标。如果拿到的有效像素不足 48px，放在统一的圆角底板上居中显示，避免列表风格杂乱。
- 打包应用使用清单里的 Logo。
- 图标缓存为 PNG：`%LOCALAPPDATA%\TaskEase\IconCache\<键哈希>.png`。

### 应用键

规则以“应用键”为索引，对应 macOS 的 bundle identifier：

- 打包应用：`pkg:<PackageFamilyName>`
- 非打包应用：`exe:<主程序路径>`。路径的规范化规则：
  1. 全部转为小写。
  2. 环境变量位置写回占位符：`%localappdata%`、`%appdata%`、`%programfiles%`、`%programfiles(x86)%`。
  3. 版本目录（形如 `app-\d+(\.\d+)+` 或 `\d+(\.\d+){1,3}` 的整段）替换为 `*`。

  例：`exe:%localappdata%\discord\*\discord.exe`。

规范化函数放在 te-model，用例放在 `fixtures/app-keys.json`。

## 进程身份

`ProcessIdentity = { pid, create_time(FILETIME u64), user_sid, image_path }`

- 所有控制操作执行前，用 `OpenProcess` 拿到句柄，再核对 `GetProcessTimes` 的创建时间和映像路径；有一项不一致就放弃操作。
- 打开进程时只申请需要的最小访问权限（见 05）。
- 采样阶段可以使用路径缓存，以 `(pid, create_time)` 为键。

## 采样与调度

完全沿用 macOS 的 `SamplingPolicy`：显示采样与控制采样分开，各自保留计数基线。下一次唤醒取三者中最早的期限：

- 显示间隔：1、2、5 或 10 秒，只在 UI 订阅了显示数据时生效。
- 控制检查：存在生效规则时每 2 秒一次。
- 后台等待期限：某个应用离开前台后，第 N 秒到期。

没有显示需求、也没有需要执行的规则时，不设置任何定时器，只等待事件。

- 进程快照：一次 `NtQuerySystemInformation(SystemProcessInformation)` 取得全部进程的 CPU 时间、私有工作集、I/O 计数、线程数和上下文切换次数，不需要逐个打开进程。
- GPU 统计、温度和网卡计数只在显示采样中读取，并共享 4 秒的硬件缓存（与 macOS 相同）。
- 前台切换事件到达后：先用缓存生成恢复计划并立即执行（回到前台的应用不用等完整扫描），再异步刷新。

## IPC 协议

传输层：

- core ↔ UI：命名管道 `\\.\pipe\TaskEase.<用户SID>.ui`。
- core ↔ svc：命名管道 `\\.\pipe\TaskEase.svc`。

两个管道都以 UTF-8 JSON Lines 传输，每行一条消息，格式为 `{"v":1,"id":…,"type":…,"body":…}`。

安全：

- UI 管道的 DACL 只允许当前用户访问。
- svc 管道允许交互式用户连接，但服务会做以下校验：用 `GetNamedPipeClientProcessId` 取得调用方 PID，打开进程并确认其映像路径等于安装目录下的 `taskease-core.exe`；调用方的会话必须是活动控制台会话或 RDP 会话。服务创建的网络规则只作用于调用方用户 SID 拥有的进程。

消息类型在 te-model 中定义为 serde 枚举。如果 UI 选用 Tauri，用 `specta` 或 `ts-rs` 导出 TypeScript 类型；如果选用 WinUI，从 te-model 生成 JSON Schema，再生成 C# 类型。

主要消息：

| 方向 | 类型 | 说明 |
| --- | --- | --- |
| UI→core | `hello` | 协议版本与 UI 版本；版本不兼容时 core 返回错误，UI 提示用户重新安装 |
| UI→core | `subscribe` | 显示需求：`{overview, apps, interval, network, gpu, selected_app}`。断开连接等于取消订阅，core 随即停止显示采样 |
| core→UI | `snapshot` | 概览、应用列表（含状态与图标路径）、规则、偏好 |
| UI→core | `set_rule` / `remove_rule` / `set_master` / `set_prefs` / `set_network_rule` / `set_frame_rule` | 编辑操作；core 校验后保存，再推送新的 snapshot |
| UI→core | `clear_data_and_quit` / `check_update` / `install_update` | |
| core→UI | `event` | 错误、更新状态、服务状态等 |
| core→svc | `apply_network_plan` | 带版本号和有效期的完整网络计划（不可变）；core 失联超时后，svc 自动撤销 |
| core→svc | `subscribe_net_stats` / `subscribe_fps` | 按需开启 ETW 会话，取消订阅即关闭 |

失联期限沿用 macOS 的做法（10 秒期限，每 2 秒续约，容忍系统节能推迟定时器）：

- core 与 svc 之间每 2 秒发一次心跳。svc 超过 10 秒没收到心跳，就撤销该 core 下发的全部网络计划。
- UI 断开对 core 的规则执行没有任何影响。

## 本地数据

位置：`%LOCALAPPDATA%\TaskEase\`。写入方式为“临时文件 + `MoveFileExW(REPLACE_EXISTING | WRITE_THROUGH)`”。

| 文件 | 内容 | 对应 macOS |
| --- | --- | --- |
| `rules.v1.json` | `{应用键: AppRule}`，字段与 macOS 同名：`enabled`、`delaySeconds`、`alwaysLimit`、`limitsPerformance`、`performance`（budget/suspend）、`cpuPercent`、`adjustsVolume`、`volumePercent`（0–90，0 为静音）、`lowersPriority`；同时写入旧版 `mode` 字段；缺少新字段时按旧 `mode` 迁移 | rules.v1 |
| `ruleApplications.v1.json` | `{应用键: {name, exePath, iconPath}}`，用于显示没在运行的应用 | ruleApplications.v1 |
| `networkRules.v1.json` | 字段与 macOS 的 `NetworkRule` 相同 | networkRules.v1 |
| `frameRules.v1.json` | `{应用键: FrameRule}`：`enabled`、`backgroundFps`、`foregroundFps`（0 表示不限）、`delaySeconds`、`gpuLowPriority` | Windows 独有 |
| `preferences.v1.json` | 外观、刷新间隔、系统应用筛选、仅前台刷新、CPU 口径、语言、实验功能开关 | preferences.v1 |
| `recovery.v1.json` | 恢复记录，见 05 | 恢复记录 |
| `usageAnalytics.v1.json` | 统计同意状态、安装 UUID、待发送事件 | usageAnalytics.* |
| `IconCache\`、`Logs\` | 图标缓存；日志按大小轮转，最多 5 × 1 MB，不记录应用名称以外的用户数据 | — |

- 读取失败或数据损坏时，把原文件改名为 `.corrupt-<时间>` 备份，规则相关文件损坏时关闭主开关，与 macOS 一致。
- 新增字段必须提供兼容的默认值。

## 恢复机制概要

详细规则见 [05 进程控制与恢复](05-ProcessControl.md)，下面是概要：

- 控制状态发生变化时写 `recovery.v1.json`。
- core 第一次控制某个进程前启动 guard，并把 Job 句柄复制给 guard。
- guard 等待 core 的进程句柄。core 正常退出前会先恢复全部进程并删除记录；如果 core 是异常退出，guard 按记录恢复。
- core 启动时如果发现遗留的恢复记录，先执行恢复，再开始工作。
- 网络计划失联后由 svc 撤销；WFP 动态会话随 svc 退出自动消失。
- 帧率限制：core 每秒在共享内存里写一次心跳时间戳。注入的 DLL 发现心跳超过 3 秒没有更新，就自动回到不限帧率。不能依赖“映射失效”：DLL 自己也持有映射视图，core 退出后映射仍然存在。
