# 验证记录

本目录保存 2026-10-10 在本机完成的验证摘要。环境为 M5 MacBook Air、macOS 27.0.1、Xcode 27.0。

- automatic-tests.json：本轮 14 项单元测试和 3 项界面测试全部通过的实际结果。
- branding-tests.json：图标更新后的 2 项界面回归测试。
- application-instance.json：不同应用副本并发启动及崩溃重开的隔离检查。
- application-delivery.json：Release 包、运行实例和 Dock 状态的交付检查。
- self-check.json：项目 build/TaskEase.app 的真实进程控制自检，只使用自建限时负载进程。
- delivery.json：应用副本、签名、运行实例数及测试进程清理的最终核对。
- overhead.json：菜单关闭、无规则时的 Debug 构建采样片段，CPU 按一个核心计算，不能换算成电池节能比例。
- snapshot-summary.json：真实只读采样的应用数量、进程分组与整机指标。
- management-preview.png、menu-preview.png：SwiftUI 界面的渲染检查，显示测试数据。

测试方法与边界见 [验证文档](../Docs/Validation.md)。

提交的摘要省略本机 PID 和临时绝对路径。原始记录保存在 `local/`，仅供本机核对，不纳入 Git。
