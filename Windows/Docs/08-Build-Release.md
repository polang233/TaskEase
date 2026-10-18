# 08 构建、打包与发布

## 开发环境

| 用途 | 环境 |
| --- | --- |
| 纯逻辑（te-model） | 任意平台：`cargo test -p te-model`，可以直接在本机 Mac 上运行 |
| Windows 代码的语法与类型检查 | Mac 上 `rustup target add x86_64-pc-windows-msvc` 后执行 `cargo check --target x86_64-pc-windows-msvc -p te-sys -p te-core`（V-14：确认能在不链接的情况下通过） |
| 构建、运行、实机验证 | Windows 11 x64 实机，或 Apple Silicon Mac 上 Parallels 中的 Windows 11 ARM |
| CI | GitHub Actions 的 `windows-2025` 运行器 |

Parallels 中的 Windows 11 是 ARM64 版。在里面构建 x64 目标没有问题，x64 程序也能通过仿真运行，但帧率注入和 GPU 统计必须在 x64 实机或 CI 上验收，仿真环境的结果不能作为依据。

**工具链**：

- Rust stable（MSVC 目标）。
- Visual Studio 2022 Build Tools：“使用 C++ 的桌面开发”工作负载和 Windows 11 SDK。
- Node.js LTS + pnpm（如果 D-04 选 Tauri）；.NET 8 SDK（如果选 WinUI）。
- Inno Setup 6。

**主要依赖**：`windows`（windows-rs）、`serde`/`serde_json`、`tokio`（current-thread，开启 `net` 特性以支持命名管道）、`tracing`、`windows-service`（服务）。新增依赖时，登记到下面的“依赖与许可证”表。

## 构建命令（Scripts/ 下，由 T0.1 建立）

```powershell
# 开发构建
cargo build -p te-core
# 全部测试（Windows）
cargo test --workspace
# Release 安装包：编译 core、svc、hook、UI，再生成 installer
pwsh Windows/Scripts/build.ps1 -Configuration Release
# 自检
build\win\TaskEase\taskease-core.exe --self-check
```

产物统一放在仓库根目录的 `build/win/` 下（已被 `.gitignore` 的 `build/` 规则覆盖）。

## 安装布局（D-05）

```
C:\Program Files\TaskEase\
├── taskease-core.exe       常驻核心（含 --guard / --self-check 模式）
├── taskease-ui.exe         界面进程（Tauri；若选 WinUI 则为其输出目录）
├── taskease-svc.exe        可选服务，用户开启网络功能后才注册
├── te-fps-hook.dll         帧率注入组件
├── WinDivert.dll / WinDivert64.sys   仅在网络限速功能中使用
├── LICENSE.txt             完整 GPLv3 文本，与仓库根目录的 LICENSE 一致
└── PostHog.json            公开接收令牌，与 macOS 版相同的配置格式
```

- **安装器**：Inno Setup，按机器安装，需要 UAC。
  - 写入 `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`，开机自启 core（在安装器的“开机启动”选项中可以取消）。
  - 安装完成后启动 core。
- **卸载**：
  1. 通知 core 恢复全部进程并退出。
  2. 停止并删除服务（会撤销 WFP 和 WinDivert 规则）。
  3. 删除程序文件。
  4. 询问用户是否删除 `%LOCALAPPDATA%\TaskEase`。
- **升级**：安装器先通过命名管道请 core 执行“恢复后退出”，等待其退出（超时 10 秒后结束进程），再覆盖文件。

## 更新

- core 启动时检查一次更新，之后每 24 小时检查一次。使用 GitHub Releases API，列出最近的 releases，只取 `win-v` 开头且不是草稿的版本（D-12）。
- 资源命名：`TaskEase-Setup-<版本>-x64.exe`。release 说明中附上 SHA-256，与 macOS 版的校验方式相同，见 `TaskEase/Services/GitHub/GitHubClient.swift`。
- 安装流程：
  1. 下载到 `%LOCALAPPDATA%\TaskEase\Updates\`。
  2. 校验大小和 SHA-256。
  3. 恢复全部受控进程。
  4. 以 `/SILENT` 启动安装器。
  5. core 退出，安装器完成后重新启动 core。

## 版本与发布（D-12）

- 版本号独立，从 `0.1.0` 开始。版本记录在 `Windows/Cargo.toml` 的 `workspace.package.version`；如果 UI 有自己的版本号，两者保持一致。
- 标签格式 `win-v0.1.0`，打在 main 上；在 GitHub 上发布时**不标记为 Latest**。
- 第一次正式发布前（T4.6），确认 macOS 版的更新检查不会受影响。

## 签名（D-10）

- 初期不签名。README 的 Windows 部分写明 SmartScreen 的处理方法：点“更多信息”，再点“仍要运行”。
- T4.5 评估：
  - SignPath Foundation 的开源项目免费签名。
  - Azure Trusted Signing 对个人开发者的地区与资格要求。
  - 签名后能否明显降低注入 DLL 和安装器被 Defender 误报的概率。

## 使用统计

字段、频率、重试和去重规则与 [../../Docs/PostHog.md](../../Docs/PostHog.md) 完全相同，只有以下差异：

- `os_name` 为 `Windows`，`os_version` 形如 `10.0.22631`。
- 新增 `frame_rule_count`。
- `network_rule_count` 只统计已启用的规则。

Debug 构建和测试使用夹具模式，不发送真实事件。`--analytics-check` 发送一条带 `is_test=true` 的合成事件。不能在源码中加入任何私人 API 密钥。

## CI（`.github/workflows/windows.yml`，由 T0.1 建立）

- 触发：`Windows/**` 路径下有改动的 push 和 PR。
- 步骤：
  1. `cargo fmt --check`
  2. `cargo clippy -D warnings`
  3. `cargo test --workspace`
  4. 构建 Release
  5. 运行 `--self-check`（CI 环境有管理员权限，只操作自建测试进程）
  6. 上传安装包作为构建产物
- 前端：`pnpm lint`、`pnpm test`、`pnpm build`。

## 依赖与许可证

| 依赖 | 用途 | 许可证 | 状态 |
| --- | --- | --- | --- |
| windows-rs | Win32/WinRT 绑定 | MIT/Apache-2.0 | 计划 |
| tokio | 异步运行时 | MIT | 计划 |
| serde / serde_json | 序列化 | MIT/Apache-2.0 | 计划 |
| windows-service | 服务框架 | MIT/Apache-2.0 | 计划 |
| Tauri 2 / window-vibrancy | 界面（D-04 待定） | MIT/Apache-2.0 | 待定 |
| Svelte 5 | 界面（D-04 待定） | MIT | 待定 |
| WinDivert 2.2 | 网络限速 | 选用 LGPLv3 | 计划，需通过 V-11 |
| retour 或 MinHook | 帧率挂钩 | BSD-2 等 | T0.7 选定 |
| Inno Setup | 安装器（只在构建时使用，不随包分发） | Inno Setup License | 计划 |

正式引入依赖后，把状态改为“已用”，并写明版本。随包分发的第三方组件，其许可证文本放在安装目录的 `ThirdPartyNotices.txt` 中。
