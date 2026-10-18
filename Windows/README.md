# TaskEase for Windows · 轻程 Windows 版

把轻程的核心体验带到 Windows 11：看清是谁在占用资源，按前后台自动限制或暂停应用，切回立即恢复。同时补上 macOS 版目前做不到的两项能力：**应用帧率限制**和**应用网络阻断/限速**。

> 本目录是 Windows 版的设计与实施文档，供人和 agent 共同推进。代码尚未开始，当前处于**阶段 0（准备与验证）**。

## 当前状态

| 项目 | 状态 |
| --- | --- |
| 阶段 | 阶段 0：准备与验证 |
| 待用户决策 | D-04 界面方案（推荐 Tauri 2，见 [界面方案](Docs/03-UI-Options.md)） |
| 进度明细 | [PROGRESS.md](PROGRESS.md) |
| 决策记录 | [DECISIONS.md](DECISIONS.md) |

## 平台目标

- **主目标：Windows 11 22H2（build 22621）及以上，x64。** 设计、测试和验收都以此为准。
- Windows 10 22H2：只求能运行，不做专门适配，不阻塞任何任务；界面缺少 Mica 和圆角属于预期。
- ARM64（骁龙 X 等）：阶段 4 之后再支持。帧率注入在 ARM64 上还要另做 x64/ARM64EC 适配。

## 阅读顺序

1. [01 范围与能力对照](Docs/01-Scope.md)：做什么、不做什么，每个功能在 Windows 上能做到什么程度。
2. [02 架构](Docs/02-Architecture.md)：进程模型、模块划分、IPC、数据格式和恢复机制。**写任何代码前必读。**
3. [03 界面方案](Docs/03-UI-Options.md)：各方案的优劣、推荐方案和评测门槛。
4. 按任务需要阅读专题文档：
   - [04 系统指标](Docs/04-Metrics.md)
   - [05 进程控制与恢复](Docs/05-ProcessControl.md)
   - [06 帧率限制](Docs/06-FrameRate.md)
   - [07 网络监控与控制](Docs/07-Network.md)
   - [08 构建、打包与发布](Docs/08-Build-Release.md)
   - [09 测试与验证](Docs/09-Testing.md)

macOS 版的行为定义仍然是参考来源：[../Docs/Requirements.md](../Docs/Requirements.md)、[../Docs/Design.md](../Docs/Design.md)、[../Docs/SystemMetrics.md](../Docs/SystemMetrics.md)、[../Docs/Networking.md](../Docs/Networking.md)、[../Docs/PostHog.md](../Docs/PostHog.md)。Windows 文档只写与 macOS 不同或新增的部分，相同的地方直接引用。

## 给 agent 的工作约定

### 开工

1. 读本文件、[PROGRESS.md](PROGRESS.md)、[DECISIONS.md](DECISIONS.md) 和 [02 架构](Docs/02-Architecture.md)。
2. 在 PROGRESS.md 里挑一个状态为 ⬜ 的任务，要求它的依赖全部为 ✅，且没有 ⏸（等待决策）标记。
3. 把状态改成 🟨，写上开始日期（YYYY-MM-DD），再动手。
4. 一次只领一个任务。拆出来的子任务追加到同一阶段的表格末尾，编号接着往下排（如 T1.5a）。

### 实施

- 只做任务描述范围内的事。发现范围外的问题，在 PROGRESS.md 的“发现的问题”里记一行，不要顺手修。
- 发现文档与事实不符（例如某个 V 验证项的结果推翻了原来的假设），先更新对应文档和 DECISIONS.md，再继续写代码。
- 影响产品行为、权限、安装方式或许可证的决定，标记 ⏸ 交给用户，不要自己拍板。
- 进程控制实验**只能用自建测试进程**（`testapps/`），不能暂停、注入或断网用户的真实应用。
- 界面文案、代码注释和提交信息用中文；类型用 `///` 简述职责，与 macOS 版保持一致。
- 许可证为 GPL-3.0-only。新增第三方依赖时，把名称、版本和许可证登记到 [08 构建与发布](Docs/08-Build-Release.md#依赖与许可证)；不兼容 GPLv3 的依赖不能引入。
- 只在用户明确要求时提交或推送，提交信息不附带 agent 署名。

### 收尾

1. 按任务的“验收”逐条自证，把证据（命令、输出摘要、截图路径）写进 PROGRESS.md 对应行的“证据”列，或写进 `Windows/Artifacts/local/` 后引用路径。
2. 构建通过、自动测试和实机验证要分别报告，不能用以前的通过记录代替本轮结果。
3. 状态改为 ✅，在“变更日志”追加一行。
4. 如果验收没过、或被外部条件卡住，状态改为 ⛔ 并写明原因，不要标记完成。

## 与 macOS 版的关系

- **不共享代码，共享行为。** macOS 版是 Swift，Windows 版的核心用 Rust。规则判定、采样期限和令牌桶这类纯逻辑，两边各自实现，用同一组 JSON 用例（`Windows/fixtures/`）保证结果一致。
- 规则格式字段与 macOS 的 `rules.v1` 保持同名同义，只把“应用标识”换成 Windows 的应用键（见 [02 架构](Docs/02-Architecture.md#应用键)）。
- 品牌色、十档占用配色和文案键名直接沿用 macOS 版：配色来源 `TaskEase/Shared/Views/MetricPalette.swift`，文案来源 `TaskEase/Resources/Localizable.xcstrings`。

## 目录规划

代码开始后按下面的结构放在 `Windows/` 下（阶段 0 的 T0.1 负责建立骨架）：

```
Windows/
├── README.md  PROGRESS.md  DECISIONS.md
├── Docs/                 设计文档
├── Cargo.toml            Rust workspace
├── crates/
│   ├── te-model/         纯逻辑与数据类型：规则、策略、采样期限、令牌桶、IPC 消息（可在 macOS 上测试）
│   ├── te-sys/           Windows API 封装（windows-rs）
│   ├── te-core/          常驻核心 taskease-core.exe（托盘、采样、控制、IPC、守护模式）
│   ├── te-service/       可选的系统服务 taskease-svc.exe（网络、ETW）
│   └── te-fps-hook/      帧率限制注入 DLL
├── ui/                   界面进程（方案由 D-04 决定）
├── testapps/             自建测试负载：CPU、D3D11/Vulkan 渲染、TCP/UDP 流量
├── fixtures/             跨平台共享的 JSON 用例
├── installer/            Inno Setup 脚本
├── Scripts/              build.ps1 等脚本
└── Artifacts/local/      本地验证输出（Git 忽略）
```
