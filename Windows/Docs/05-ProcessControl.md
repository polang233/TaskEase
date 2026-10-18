# 05 进程控制与恢复

规则判定（`Policy.status`）、取值范围和默认值与 macOS 完全一致，见 `TaskEase/Features/Rules/Policy.swift` 和 `TaskEase/Models/AppRule.swift`，te-model 按原样移植。本文写的是 Windows 上的执行方式。

一条规则在“限制后台资源”打开后，按同一生效时机执行三项可以任意组合的限制：

- **性能限制**：CPU 上限 5%–200%，滑杆拖到最左端为暂停。
- **后台音量**：0%–90%，0 为静音。
- **降低优先级**：暂停时不使用。

状态显示取影响最强的一项：暂停 > CPU 上限 > 降低优先级 > 降低音量 / 静音。

## 总原则

1. core 是唯一执行者，界面只修改规则。
2. 只撤销 TaskEase 自己施加的状态。每一步操作都要记录“改之前是什么、改成了什么”。
3. 每次操作前都核对完整的进程身份（见 02）。
4. 不接管已经被别人暂停的进程，也不改动别人设置的优先级。
5. 恢复要做到“失联也能恢复”：恢复记录、guard、启动时补偿，三道保险。

## 访问权限

| 操作 | `OpenProcess` 访问掩码 |
| --- | --- |
| 身份核对 | `PROCESS_QUERY_LIMITED_INFORMATION` |
| 暂停与恢复 | `PROCESS_SUSPEND_RESUME` |
| 加入 Job | `PROCESS_SET_QUOTA \| PROCESS_TERMINATE` |
| 优先级与 EcoQoS | `PROCESS_SET_INFORMATION \| PROCESS_QUERY_LIMITED_INFORMATION` |
| GPU 调度优先级 | 需要验证（V-04） |
| 注入（06） | `PROCESS_CREATE_THREAD \| PROCESS_VM_OPERATION \| PROCESS_VM_WRITE \| PROCESS_VM_READ \| PROCESS_QUERY_INFORMATION` |

打开失败（无权限或进程已退出）时，把该成员标记为“不可控”。只要应用中有一个成员不可控，状态就显示为“部分受控”，但不报错。

## 暂停应用（suspend）

- **执行**：对每个成员调用 `NtSuspendProcess`（ntdll 导出、未公开文档的接口，Process Explorer 和资源监视器都在用）。在恢复记录中给该成员的 `suspend_count` 加 1。
- **恢复**：按 `suspend_count` 调用相同次数的 `NtResumeProcess`。挂起计数是叠加的，所以别人施加的挂起不会被我们解除。
- **不接管已暂停的进程**：从快照中读取各线程的 `ThreadState == Waiting` 且 `WaitReason == Suspended`。如果全部线程都处于挂起状态，并且不是我们挂起的，就跳过该进程。系统暂停的 UWP 应用会被这条规则自然跳过。
- **新成员**：应用被暂停期间出现的新成员，在下一次控制检查（2 秒）时补上暂停。
- **风险**（界面提示文案沿用 macOS 版的“完全暂停……”并补充以下内容）：
  - 被暂停的窗口在用户与它交互约 5 秒后，会被系统显示为“未响应”。正常情况下，用户点到它时它已经成为前台并恢复，不会出现。
  - 少数程序用 `SendMessage`（不带超时）向全部顶层窗口广播消息，可能被暂停的窗口卡住。遇到兼容问题时，加入应用级拒绝名单（`te-sys/deny.rs`）。
  - 暂停期间，音频、下载、通知和网络心跳都会停止，与 macOS 相同。

## 限制 CPU（budget）

### 主方案：Job Object 硬上限（D-13）

- 每个受控应用一个 Job，命名为 `Local\TaskEase.Cpu.<应用键哈希>`。
- 设置 `JOBOBJECT_CPU_RATE_CONTROL_INFORMATION`，`ControlFlags = ENABLE | HARD_CAP`，`CpuRate = round(单核百分比 ÷ 逻辑核心数 × 100)`，范围限制在 1–10000（单位为 1/100 个百分点）。
  - 例：16 个逻辑核心、上限 20% 单核，`CpuRate = round(20 / 16 × 100) = 125`，即整机的 1.25%。
- 用 `AssignProcessToJobObject` 把各成员加入 Job。成员之后创建的子进程会自动加入同一个 Job。
- **解除**：把 `ControlFlags` 设为 0。进程加入 Job 后无法移出，所以解除只能是“取消上限”。之后回到前台再进入后台时，复用同一个 Job。
- **嵌套**：Windows 8 起支持 Job 嵌套。Chrome 和 Electron 的沙箱进程本身就在 Job 中，需要验证能否加入（V-03）。加入失败的成员显示为“不可控”。

### 已知风险：Job 上限可能遗留

如果 core 和 guard 同时异常退出，Job 上限会一直生效。原因是命名 Job 没有任何句柄时，名称会从命名空间消失，之后无法再按名称打开它。对策：

1. core 把每个 Job 的句柄用 `DuplicateHandle` 复制一份到 guard 进程。只要 guard 还活着，就能解除上限。
2. 如果两者都崩溃，上限会一直保持到受控应用重启为止。下次 core 启动时，如果发现恢复记录中有 Job 条目，但已经无法打开对应的 Job，就提示用户：“某应用可能仍受 CPU 限制，重启该应用即可解除”。
3. V-03 需要实测“名称消失”的行为。如果风险不可接受，改用下面的备选方案。

### 备选方案：轮流暂停（与 macOS 相同）

移植 `BudgetCredit`：每 100 ms 检查一次额度，额度用完就暂停全部成员，额度恢复后继续。这种方式更容易恢复（遗留的只是挂起状态，由 guard 解除），但唤醒次数更多。不论默认用哪种方式，te-model 都保留这段实现和它的用例。

## 降低优先级（gentle）

依次执行以下操作，并分别记录原值：

1. `SetPriorityClass(IDLE_PRIORITY_CLASS)`，记录原来的优先级类。
2. EcoQoS：`SetProcessInformation(ProcessPowerThrottling, {ControlMask = EXECUTION_SPEED, StateMask = EXECUTION_SPEED})`。
3. 内存优先级：`SetProcessInformation(ProcessMemoryPriority, MEMORY_PRIORITY_LOW)`。
4. （可选）I/O 优先级：`NtSetInformationProcess(ProcessIoPriority, VeryLow)`，未公开文档，默认关闭，需要单独验证。

**恢复**：

- 只在当前值仍然等于我们设置的值时才改回原值。如果应用自己改过（Chrome 等会自行调整优先级），就不再动它。
- 降低优先级期间不与应用反复争夺设置：只在成员加入时执行一次。

## 降低 GPU 优先级（新增，取决于 V-04）

- `D3DKMTSetProcessSchedulingPriorityClass(hProcess, D3DKMT_SCHEDULINGPRIORITYCLASS_IDLE)`；恢复时设回之前读取到的值（`D3DKMTGetProcessSchedulingPriorityClass`）。
- 作为帧率规则的附加选项（`FrameRule.gpuLowPriority`），也可以单独使用。
- 它只在 GPU 资源争抢时起作用，不会降低应用单独运行时的帧率。界面需要说明这一点。

## 后台音量（不需要任何权限）

macOS 版要用 Core Audio 进程截取，所以需要“系统录音”权限；非静音档位还要经过聚合设备转播。Windows 的音频会话接口本身就支持按应用调音量（系统“音量合成器”用的就是它），不需要权限和管理员，也不会增加延迟。

- **枚举**：
  1. 用 `IMMDeviceEnumerator::EnumAudioEndpoints(eRender, DEVICE_STATE_ACTIVE)` 列出全部输出设备（应用可能不在默认设备上发声）。
  2. 对每台设备调用 `IAudioSessionManager2::GetSessionEnumerator`，从每个会话的 `IAudioSessionControl2::GetProcessId` 取得 PID，归入所属应用。
- **调整**：用会话的 `ISimpleAudioVolume` 执行 `SetMasterVolume` / `SetMute`，`EventContext` 传 TaskEase 自己的 GUID，便于在回调里区分是不是自己改的。增益映射与 macOS 一致：幅度 = (百分比 ÷ 100)²。
- **新会话与设备变化**：
  - 用 `IAudioSessionManager2::RegisterSessionNotification` 监听新会话。注意：必须先调用一次 `GetSessionEnumerator`，通知才会生效。
  - 用 `IMMNotificationClient` 监听设备增减和默认设备变化。
  - 这两项都是事件驱动，不需要轮询。只有存在生效中的音量规则时才注册。
- **恢复**：
  - 记录每个会话原来的音量和静音状态，回到前台时写回。
  - 写回前先比较：如果当前值已经不是我们设置的值（说明用户在音量合成器里手动改过），就不再动它。
- **持久化风险**：Windows 会按应用记住会话音量，应用重启后可能仍然保持被调低的值（V-16 验证）。因此音量调整也要写进恢复记录，由 guard 和启动补偿负责恢复。这一点与 macOS 不同：macOS 的截取对象随本应用退出自动销毁。
- **归属**：Chromium/Electron 可能由单独的音频服务子进程发声，按应用分组后会归到同一个应用（V-16 验证）。

## 前后台与时机

- 前台来源是 `EVENT_SYSTEM_FOREGROUND` 回调中的 HWND，通过 `GetWindowThreadProcessId` 得到 PID。
  - 如果窗口类是 `ApplicationFrameWindow`（宿主是 ApplicationFrameHost.exe），要在子窗口中找到类为 `Windows.UI.Core.CoreWindow` 的窗口，取它的 PID（UWP 应用）。
  - 如果前台窗口属于 TaskEase 自己的界面，保留“上一个前台应用”的状态不变，这样在 TaskEase 里编辑规则时，被编辑的应用不会被立刻当作后台。
- “隐藏”：应用的全部顶层窗口都最小化或不可见时，视同后台。这对应 macOS 的 `isHidden`，用 `EVENT_SYSTEM_MINIMIZESTART`/`MINIMIZEEND` 触发重新评估。
- 时间使用 `QueryUnbiasedInterruptTime`，不计入睡眠时间。

## 恢复记录（`recovery.v1.json`）

```json
{
  "v": 1,
  "owner": {"pid": 1234, "createTime": 133000000000000000},
  "entries": [
    {
      "appKey": "exe:%localappdata%\\discord\\*\\discord.exe",
      "process": {"pid": 5678, "createTime": 133000000000000001, "image": "C:\\...\\Discord.exe"},
      "suspendCount": 1,
      "job": "Local\\TaskEase.Cpu.ab12cd34",
      "priority": {"original": "NORMAL", "applied": "IDLE"},
      "ecoQos": true,
      "memoryPriority": {"original": 5, "applied": 2},
      "gpuPriority": {"original": "NORMAL", "applied": "IDLE"},
      "audio": [{"device": "{0.0.0.00000000}.{…}", "session": "会话实例标识",
                 "original": {"volume": 1.0, "muted": false}, "applied": {"volume": 0.09, "muted": false}}],
      "fpsHooked": false
    }
  ]
}
```

- 只在“控制归属”变化时写入（新增或解除一项控制），平时不写，与 macOS 相同。
- 恢复时逐项核对 `pid + createTime + image`。进程已经退出或身份不一致的条目直接丢弃。如果路径变了，不会再新增限制，但仍然会解除之前施加的暂停（与 macOS 一致）。

## 生命周期事件

| 事件 | 处理 |
| --- | --- |
| 回到前台 | 立即用缓存生成恢复计划并执行，不等待扫描 |
| 关闭主开关、移除或关闭规则 | 立即恢复相关应用 |
| 睡眠 / 休眠（`PowerRegisterSuspendResumeNotification` 收到 `PBT_APMSUSPEND`） | 同步恢复全部受控进程；网络计划下发 `revoke_all`；结束 guard |
| 唤醒（`PBT_APMRESUMEAUTOMATIC`） | 重新扫描并重新开始计时；处于后台的应用重新开始等待 |
| Modern Standby | 是否会收到上面的通知，需要 V-13 验证；如果收不到，改为监听 `GUID_CONSOLE_DISPLAY_STATE` 的屏幕关闭事件 |
| 关机或注销（`WM_QUERYENDSESSION`） | 先同步恢复全部受控进程，再返回 TRUE，让被暂停的应用有机会保存数据 |
| 锁屏、切换用户 | 不做特殊处理，前台事件会自然到来 |
| core 正常退出、更新、“清除数据并退出” | 恢复全部 → 撤销网络计划 → 删除恢复记录 → 通知 guard 退出 |
| core 异常退出 | guard 按恢复记录恢复：挂起、Job 上限、优先级、后台音量都撤销；帧率依靠心跳超时自动解除 |
| guard 异常退出 | core 立刻重新启动一个 guard，并重新复制 Job 句柄 |
| core 启动时发现遗留记录 | 先恢复，再开始正常工作；无法打开的 Job 按前文的已知风险提示用户 |

## guard 模式

- 启动参数：`taskease-core.exe --guard <core_pid> <core_create_time>`。
- 用 `OpenProcess(SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION)` 打开 core，核对身份后执行 `WaitForSingleObject(INFINITE)`，没有任何轮询。
- core 通过一个匿名管道向 guard 传递 Job 句柄，并发送“正常结束”标记。收到标记后 guard 直接退出，不执行恢复。
- guard 不加载托盘、界面或网络相关模块，目标私有工作集不超过 2 MB。

## 自检（`--self-check`）

对应 macOS 的 `Scripts/run-self-check.sh`：

1. 启动 `testapps/cpu-burner`（多线程满载）。
2. 依次验证以下行为，并分别测量：
   - 暂停后 CPU 为 0，恢复后回升。
   - Job 上限 20% 时，30 秒平均值在 15%–25% 之间。
   - 降低优先级后，优先级类变为空闲，EcoQoS 已开启，恢复后变回原值。
   - 强制结束 core（模拟崩溃）后，guard 在 1 秒内完成恢复。
3. 输出 JSON 报告到 `Windows/Artifacts/local/self-check-<时间>.json`。

自检只操作自己创建的测试进程。
