# 04 系统指标

指标的展示规则、配色、卡片布局和刷新策略与 [../../Docs/SystemMetrics.md](../../Docs/SystemMetrics.md) 相同。本文只写数据来源和与 macOS 不同的口径。

## 数据来源

| 指标 | Windows 来源 | 口径 | 与 macOS 的差异 |
| --- | --- | --- | --- |
| 应用 CPU | `SYSTEM_PROCESS_INFORMATION.UserTime + KernelTime` 的差分 ÷ 墙钟时间 | 一个逻辑核心满载为 100%；“整机口径”再除以逻辑核心数 | 相同 |
| 整机 CPU | `GetSystemTimes` 的差分：1 − idle ÷ (kernel + user) | 所有核心合计，满载为 100% | kernel 时间里包含了 idle，计算时要先扣除 |
| 应用内存 | `SYSTEM_PROCESS_INFORMATION.WorkingSetPrivateSize` 各成员之和 | 私有工作集 | macOS 用的是 footprint。Windows 的私有工作集不包括已换出到页面文件的部分，界面标注“内存（私有）” |
| 整机内存 | `GlobalMemoryStatusEx` 加 `GetPerformanceInfo` | 已用 = 总量 − 可用；详情显示已提交量与上限 | Windows 的“可用”已经包含备用列表（缓存），口径接近 macOS 的“排除可回收缓存” |
| 压缩内存 | 系统进程 `Memory Compression` 的工作集 | 已包含在已用内存中 | 只在详情里显示 |
| 交换 | 页面文件使用量：`GetPerformanceInfo` 或 `NtQuerySystemInformation(SystemPageFileInformation)` | | |
| 应用 I/O | `ReadTransferCount`、`WriteTransferCount` 的差分 | 包含文件、网络和设备的全部 I/O | 界面标为“I/O 读取/写入”，不叫“磁盘” |
| 上下文切换 | 各线程 `ContextSwitches` 之和的差分 | 次/秒 | 用来替代 macOS 的“中断唤醒”，界面使用新文案 |
| 应用 GPU | `D3DKMTQueryStatistics(D3DKMT_QUERYSTATISTICS_PROCESS_NODE)`，按适配器、节点和进程取 `RunningTime` 的差分 | 每个引擎单独计算占比；应用 GPU 取该应用在各 3D/计算/复制引擎上的最大占比，上限 100% | 比 macOS 细：可以单独显示视频解码引擎。备选方案为 PDH 的 `\GPU Engine(*)\Utilization Percentage`（V-05） |
| 整机 GPU | 各引擎节点 `RunningTime` 差分，取最大值 | 与任务管理器一致 | 有多块显卡时，显示占用最高的那块，详情里分别列出 |
| GPU 温度 | `D3DKMTQueryAdapterInfo(KMTQAITYPE_ADAPTERPERFDATA).Temperature` | 单位是 0.1 °C | 部分驱动或核显不提供，这时隐藏该项（V-06） |
| 热区 | `\Thermal Zone Information(*)\Temperature`（PDH） | ACPI 热区，不代表芯片温度 | 只在详情显示“热区”，不放到顶部温度位置（V-06） |
| 整机网速 | `GetIfTable2`，筛选 `HardwareInterface`，排除回环与隧道接口 | 64 位计数差分，每个接口独立基线 | 同 macOS 的基线重建规则 |
| CPU 型号、核心 | 注册表 `HARDWARE\DESCRIPTION\System\CentralProcessor\0\ProcessorNameString`；`GetLogicalProcessorInformationEx(RelationProcessorCore)` 中的 `EfficiencyClass` | 按效率等级分组，即性能核与能效核 | 对应 macOS 的 `hw.perflevelN` |
| GPU 型号、显存 | `IDXGIFactory6::EnumAdapterByGpuPreference` 或 `D3DKMTQueryAdapterInfo` | 只在第一次打开卡片时读取，结果缓存 | 不加载完整 D3D 设备 |
| 按应用网速 | 服务的 ETW 会话，见 07 | | B 级，需要服务 |
| 按应用帧率 | 服务的 ETW 会话（`Microsoft-Windows-DxgKrnl` 的 Present 事件，方法参考 PresentMon），见 06 | | B 级，Windows 独有 |

## 画面合成估算（dwm.exe）

对应 macOS 的 WindowServer 估算，方法相同：

1. 读取 dwm.exe 在 3D 引擎上的 GPU 占比 `G_dwm`，以 5% 为底线，超出部分为 `E = max(0, G_dwm − 5%)`。
2. 找出“正在显示视频画面”的应用：该应用的成员进程在视频解码引擎（`VideoDecode`）上有运行时间，并且应用有可见窗口。
   - 可见窗口的条件：`IsWindowVisible`，不是最小化状态，并且 `DWMWA_CLOAKED == 0`。
3. 计算每个这类应用的可见窗口面积（与显示器求交，再减去被上层窗口遮挡的部分，可以用矩形近似），按面积比例把 `E` 分给这些应用。
4. 分到的这部分加到应用 GPU 上（总值上限 100%），在卡片中标注“画面合成（估算）”。
5. 没有任何应用在解码视频时，不枚举窗口。

GPU 卡片中的“占用来源”列表和“未归属到进程”行，规则与 macOS 相同。

## 采样开销约束

- 进程快照每轮只调用一次 `NtQuerySystemInformation`。缓冲区按上次实际用量的 1.5 倍预先分配。
- D3DKMT 统计需要为每个进程打开句柄（`PROCESS_QUERY_LIMITED_INFORMATION`）。句柄按 `(pid, create_time)` 缓存，进程退出后关闭。只在显示采样且需要 GPU 数据时读取。
- PDH 查询只在需要热区数据时打开，界面关闭时释放。
- 所有系统读取都在工作线程中执行。
