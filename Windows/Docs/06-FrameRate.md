# 06 帧率限制（Windows 独有，实验功能）

## 目标与边界

- **目标**：应用离开前台后，把它的渲染帧率限制在设定值（例如 5、10、30 fps），切回前台后恢复为不限或前台上限。主要用于降低远程桌面、视频播放器、游戏和 Electron 应用在后台的 GPU 与功耗。
- **能保证的**：挂钩成功的应用，`Present` 调用频率不超过设定值。
- **不能保证的**：
  - 应用内部的视频解码、网络接收和 CPU 计算不一定随帧率下降。比如远程桌面在后台可能照样解码每一帧，只是不再呈现。
  - 效果要按应用实测。界面上显示的是“呈现帧率”，不是“功耗降低多少”。
- **默认关闭。** 设置里打开“帧率限制（实验）”后，规则编辑器才出现帧率区域。每个应用还要单独开启。

## 方案对比

| 方案 | 能否随前后台切换 | 是否需要注入 | 覆盖范围 | 风险 | 用途 |
| --- | --- | --- | --- | --- | --- |
| **A. Present 挂钩注入** | 能 | 是 | D3D10/11/12、Vulkan、OpenGL；不限显卡厂商 | 反作弊、安全软件、部分进程拒绝加载未签名 DLL | 主方案 |
| B. GPU 调度优先级 | 能 | 否 | 所有使用 GPU 的应用 | 低；只在争抢时有效，不是上限 | 辅助，可与 A 叠加 |
| C. Vulkan 隐式层 | 只在启动时生效，之后可以通过共享内存调整 | 否（官方的层机制） | 仅 Vulkan 应用 | 低 | 后续可以替代 A 中的 Vulkan 部分 |
| D. NVIDIA 驱动配置文件“最大帧速率” | 否，只在启动时生效 | 否 | 仅 NVIDIA 显卡 | 低 | 后续用于“始终限制”的规则 |
| E. 按周期暂停或限制 CPU | 能 | 否 | 所有应用 | 画面卡顿，不是真正的限帧 | 不采用 |

## 主方案 A 的设计

### 组件

- **te-fps-hook.dll**：注入后安装挂钩。
  - 挂钩库：使用 Rust 的 `retour`，或 MinHook（BSD-2）的绑定。在 T0.7 中选定一个，并登记许可证。
  - 挂钩目标：
    - `IDXGISwapChain::Present`、`IDXGISwapChain1::Present1`：先创建一个临时的 D3D11 设备和交换链，从虚函数表中取到函数地址，再挂钩。
    - `vkQueuePresentKHR`：挂钩 `vulkan-1.dll` 的导出函数，或通过 `vkGetDeviceProcAddr`。
    - `wglSwapBuffers` / `SwapBuffers`。
  - DLL 被加载时只检查目标模块是否已经加载。如果还没加载，挂钩 `LoadLibraryExW` 等待它加载，不主动加载图形库。
- **注入器**（在 core 中）：
  1. 在目标进程中用 `VirtualAllocEx` 分配内存，写入 DLL 的完整路径。
  2. 调用 `CreateRemoteThread(LoadLibraryW)`。
  3. 等待线程结束，确认加载成功。
  - 注入器与目标进程的架构必须一致。首版只支持 x64 进程。
- **共享内存**：每个目标进程一份，名称为 `Local\TaskEase.Fps.<pid>.<createTime>`。内容：

  ```c
  struct FpsShared {
      uint32_t version;
      uint32_t target_fps;      // 0 = 不限
      uint64_t heartbeat_qpc;   // core 每秒写一次
      uint64_t presented;       // DLL 累计呈现次数，供自检使用
      uint32_t hook_status;     // 位标志：DXGI / Vulkan / GL 已挂钩、失败原因
  };
  ```

### 限帧逻辑（DLL 内）

1. 每次进入 `Present` 时读取 `target_fps` 和 `heartbeat_qpc`。如果心跳超过 3 秒没有更新，视同 `target_fps = 0`（core 已经失联，不再限制）。
2. 计算下一帧的截止时间 `deadline = last + 1/target`，用高精度可等待计时器（`CREATE_WAITABLE_TIMER_HIGH_RESOLUTION`）睡到截止时间，然后调用原函数。
3. 如果当前时间已经超过截止时间超过一帧，就以当前时间重新起算，避免积累“欠账”后连续快速呈现。
4. 不丢帧，不改变 `Present` 的参数（`SyncInterval` 和 flags 原样传递）。

### 卸载

- 不卸载 DLL。在挂钩仍然有效的情况下卸载 DLL 有让目标进程崩溃的风险。
- “解除”的做法是把 `target_fps` 设为 0。DLL 会一直留在目标进程中，直到该进程退出。
- 恢复记录中记下 `fpsHooked = true`，只用于展示，不需要额外的恢复动作。

### 注入目标的选择

- 只注入应用中实际执行呈现的成员进程：
  - 进程已经加载了 `dxgi.dll`、`vulkan-1.dll` 或 `opengl32.dll`（用 `EnumProcessModulesEx` 检查），并且在 GPU 3D 引擎上有运行时间。
  - Chromium 和 Electron 应用：通常是命令行带 `--type=gpu-process` 的成员（V-09）。
- **拒绝注入**的情况：
  - 已知反作弊模块：进程或同组成员加载了 EasyAntiCheat、BattlEye、Vanguard（vgk/vgc）、nProtect、ACE 等模块，或者路径中有这些目录。名单维护在 `te-sys/anticheat.rs`。
  - 已提权、受保护、属于其他用户的进程。
  - 开启了“仅允许微软签名 DLL”缓解策略的进程：用 `GetProcessMitigationPolicy(ProcessSignaturePolicy)` 检查。
  - TaskEase 自身，以及 `%WINDIR%` 下的进程。
- 注入失败时，在界面中显示具体原因：无权限、受保护、签名策略、反作弊、架构不符、未发现呈现调用。

### 界面

- 规则编辑器中新增“帧率”卡片，包含以下设置：
  - 后台帧率：不限 / 5 / 10 / 15 / 30 / 60，或自定义 1–240。
  - 前台帧率：默认不限。
  - 生效时机：复用 CPU 规则的等待档位。
  - 附加选项：同时降低 GPU 优先级。
- 状态行显示：已挂钩（DXGI）· 当前约 10 fps / 未发现呈现调用 / 不支持：<原因>。
- 首次开启时弹出说明：“需要向该应用加载 TaskEase 组件，部分游戏的反作弊或安全软件可能拦截或误报。”用户确认后才执行注入。

### 帧率显示（B 级，需要服务）

服务开启 ETW 会话，订阅 `Microsoft-Windows-DxgKrnl` 的 Present 相关事件（方法参考 PresentMon，MIT），按 PID 统计每秒呈现次数，显示为应用的 FPS 指标。

- 只在界面订阅时运行，取消订阅即关闭会话。
- 这样用户不开启注入也能看到各个应用的帧率，便于先观察再决定是否限制。

## 验证项

| 编号 | 内容 | 通过标准 |
| --- | --- | --- |
| V-08 | 用自建 `testapps/d3d11-spinner`（不限帧，不开垂直同步）和 `testapps/vk-spinner` 验证限帧 | 设为 10 fps 时，PresentMon 测得 9–11 fps；切换到不限后 1 秒内恢复；core 被强制结束后 3–4 秒内恢复不限；目标进程不崩溃 |
| V-09 | 用自建的最小 Electron 测试应用（只加载 testapps 的本地页面）验证 Chromium 系应用 | 确认能否注入 gpu-process、限帧是否生效，记录签名策略对加载的影响 |
| V-04 | GPU 调度优先级 | 两个自建 spinner 争抢 GPU 时，被降级的一方帧率明显下降；单独运行时帧率不变；记录所需的访问权限 |

V-08 或 V-09 不通过时，按结果调整范围（例如只支持 DXGI），并在 DECISIONS.md 中记录。

## 安全与发布

- 注入 DLL 和注入行为容易被安全软件当作可疑。正式发布前应完成代码签名（D-10）。在此之前，界面注明“未签名的测试功能”。
- 不向任何进程注入网络或文件相关的代码。DLL 只做限帧，不读写目标进程的其他数据。
