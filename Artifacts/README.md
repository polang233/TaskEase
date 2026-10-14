# 验证记录

本目录保存各轮在本机完成的验证摘要。环境为 M5 MacBook Air、macOS 27.0.1、Xcode 27.0；各 JSON 记录自己的采样时间与条件。

- automatic-tests.json：外围功能回归的 51 项单元、网络采样、统计调度、数据清理与窗口生命周期测试和 8 项界面测试全部通过的实际结果。
- statistics-and-icons.json：三块统计卡片、国家归属去重、图标生成流程和候选预览的核对。
- periphery-update.json：公开统计、实验网络设置、关于尺寸与展开交互的最终核对。
- usage-statistics.jpg：公开看板的带日期 README 快照，点击 README 图可打开持续更新的公开页面。
- posthog-update.json：六小时调度、扩展字段和旧记录兼容调整的 50 项测试及 Release 核验。
- posthog-integration.json：Release 客户端发送合成事件、PostHog 接收及统计看板配置的实际核验。
- branding-tests.json：2026-10-10 图标更新后的 2 项界面回归测试。
- branding-resources.json：叠层图标、18pt 菜单栏模板、编译尺寸、签名及界面预览核验。
- system-overview.json：关于与统计窗口、内存与全局网速、M5 温度读数、只读成本及自动测试核验。
- application-instance.json：不同应用副本并发启动及崩溃重开的隔离检查。
- application-delivery.json：Release 包、随包许可证、运行实例、Dock 状态和自动测试的交付检查。
- self-check.json：项目 build/TaskEase.app 的真实进程控制自检，只使用自建限时负载进程。
- delivery.json：应用副本、签名、运行实例数及测试进程清理的最终核对。
- foreground-refresh.json：管理窗口打开但应用在后台时的前台刷新选项开销验证。
- overhead.json：窗口不可见、无启用规则、桌面锁定时的 Release 构建空闲采样，CPU 按一个核心计算，不能换算成电池节能比例。
- snapshot-summary.json：真实只读采样的应用数量、进程分组与整机指标。
- network-overhead.json：网络监控可见与后台状态的 CPU、主进程物理内存与子进程开销。
- network-snapshot.json：原生网络计数与速度的实际只读摘要。
- network-rules-preview.png：网络规则配置及待启用状态的界面预览。
- paused-preview.png：管理窗口暂停刷新时的系统概览。
- management-preview.png、menu-preview.png、settings-preview.png：实际 SwiftUI 视图的离屏渲染，使用示例模型；可通过 `Scripts/render-previews.sh` 更新。
- about-preview.png、statistics-preview.png：关于页与独立使用统计窗口的示例数据渲染。
- screenshots/management.jpg、screenshots/settings.jpg：2026-10-14 从本机轻程 1.4.7 截取的实际运行界面，README 使用这两张截图；繁体中文、浅色外观，应用占用为截图时的数据。

测试方法与边界见 [验证文档](../Docs/Validation.md)。

提交的摘要省略本机 PID 和临时绝对路径。原始记录保存在 `local/`，仅供本机核对，不纳入 Git。
