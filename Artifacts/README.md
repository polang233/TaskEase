# 验证记录

本目录保存 2026-10-10 在本机完成的验证摘要。环境为 M5 MacBook Air、macOS 27.0.1、Xcode 27.0。

- automatic-tests.json：本轮 37 项单元、网络采样、数据清理与窗口生命周期测试和 6 项界面测试全部通过的实际结果。
- branding-tests.json：图标更新后的 2 项界面回归测试。
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
- management-preview.png、menu-preview.png、settings-preview.png：SwiftUI 界面的渲染检查，显示测试数据。

测试方法与边界见 [验证文档](../Docs/Validation.md)。

提交的摘要省略本机 PID 和临时绝对路径。原始记录保存在 `local/`，仅供本机核对，不纳入 Git。
