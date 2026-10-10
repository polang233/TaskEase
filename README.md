# TaskEase · 轻程

TaskEase 是原生 macOS 菜单栏工具，用于查看应用占用，并按前后台状态管理选定应用的 CPU 资源。

## 首版功能

- 显示应用及其自有辅助进程的 CPU、物理内存和磁盘活动。
- 显示整机 CPU、GPU 驱动估计值和系统热状态。
- 为应用设置不管理、温和后台调度或 CPU 预算。
- 后台等待默认 3 秒后应用规则，回到前台立即恢复。
- 暂停全部自动管理、恢复进程、退出时清理控制状态。

CPU 百分比按单核计算，100% 约等于一个核满载。CPU 预算是平均额度，不能代替精确帧率或 GPU 配额。GPU 数据来自驱动统计，只代表整机，缺失时显示不可用。

## 运行

双击 `build/TaskEase.app` 启动本机 Release 应用。启动会打开管理窗口，并在菜单栏显示双叶图标。管理窗口打开或最小化时保留 Dock 入口，关闭窗口后继续菜单栏管理。重复启动会打开已有实例的窗口。

在项目根目录执行以下命令生成应用包：

```sh
sh Scripts/build-app.sh
```

所有应用默认不管理，需主动设置规则。应用包采用本机签名，供本机使用；分发到其他电脑需要单独完成签名与公证。`build/` 为本机产物目录。

## 开发

用 Xcode 27 打开 TaskEase.xcodeproj，选择 TaskEase / My Mac。最低目标为 macOS 14。应用以当前用户身份运行，不安装管理员服务。进程控制使用独立同用户恢复进程；只有正在管理后台应用时才启动。

应用目标采用非沙箱配置，便于读取和管理同用户进程。系统保护进程和共享系统服务只用于观察。

## 目录

| 路径 | 内容 |
| --- | --- |
| `TaskEase/` | 原生界面、规则、采样与进程控制 |
| `TaskEase.xcodeproj/` | Xcode 工程与目标配置 |
| `TaskEaseTests/` | 策略、预算与配置单元测试 |
| `TaskEaseUITests/` | 管理窗口与交互测试 |
| `Docs/` | 需求、设计、使用与验证说明 |
| `Scripts/` | 进程控制自检与只读开销测量 |
| `Artifacts/` | 验证摘要与界面预览 |
| `Branding/` | 图形源文件、图标预览与制作说明 |

## 验证

在 Xcode 中按 Command-U 运行测试。进程控制自检需传入已构建应用的可执行文件路径，在项目根目录执行：

```sh
sh Scripts/run-self-check.sh /path/to/TaskEase.app/Contents/MacOS/TaskEase
```

自检只控制自己创建的限时负载进程。CPU 预算、异常恢复和实际测量边界见 [验证文档](Docs/Validation.md)。

## 文档

- [需求与验收条件](Docs/Requirements.md)
- [设计与恢复机制](Docs/Design.md)
- [验证方法与结果](Docs/Validation.md)
- [使用说明](Docs/Usage.md)
- [图标设计与资源](Branding/README.md)

Release 构建、17 项自动测试、跨应用副本的单实例检查和进程控制自检通过。实际记录与边界见 [验证文档](Docs/Validation.md)。
