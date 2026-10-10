# TaskEase 验证

## 实际环境

2026-10-10，M5 MacBook Air，24 GB，macOS 27.0.1，Xcode 27.0。最低部署目标为 macOS 14。Release 包同时包含 arm64 和 x86_64，实机验证在本机 arm64 环境完成。

## 应用启动与窗口

- Release 构建成功，应用签名通过严格验证，运行库来自系统。
- 14 项 Swift Testing 单元测试通过，包括菜单栏 NSImage 的 18 点逻辑尺寸、template 属性、实例锁释放与重新取得、测试环境隔离，以及真实 NSWindow 的复用和 Dock activation policy。
- 管理窗口打开时实际运行实例采用 regular policy，正常实例数为 1。
- 隔离测试使用两份不同路径的应用，4 个并发重复启动请求均结束，只保留 1 个界面实例。
- 强制结束测试实例后，同一实例锁可由另一份应用重新取得，恢复启动通过。
- 17:22 本轮 3 项 XCTest 界面测试通过，覆盖搜索、全局管理开关，以及关闭窗口后恢复同一进程和窗口。
- 共 17 项自动测试全部通过。界面测试通过 Launch Services 恢复应用，单实例并发检查使用独立进程测试。
- 11:43 的图标更新记录中，原有 2 项界面测试通过。

记录保存在 `Artifacts/automatic-tests.json`、`application-instance.json` 和 `application-delivery.json`。单实例检查使用测试数据和独立命名空间，真实应用规则保持各自的存储域。

## 进程控制自检

对 `build/TaskEase.app` 的 Release 可执行文件运行自检通过。只使用自建限时负载进程，每个进程最长运行 20 秒。

| 检查 | 实际结果 |
| --- | --- |
| 单进程基线 | 100.43% 单核 CPU |
| 单进程 20% 预算 | 20.46% |
| 解除预算 | 100.03% |
| 两进程合计 20% 预算 | 19.60% |
| 温和调度与解除 | 通过 |
| 控制器失联 3 秒 | 恢复通过 |
| 控制进程强制结束 | 主应用补偿恢复通过 |
| 两进程同时解除 | 通过 |

CPU 预算是平均额度，存在短时超额和调度误差。

## 采样与开销记录

早先 Debug 构建在菜单关闭、无应用规则时，18 秒片段约占 0.55% 单核 CPU，物理 footprint 约 16.4 MiB。数据来自 `Artifacts/overhead.json`，不代表当前 Release 的续航或功率测量。

真实只读快照读到 44 个应用，43 个有可读进程数据，10 个包含多个自有进程。数量摘要保存在 `Artifacts/snapshot-summary.json`。

## 使用边界

- GPU 是整机驱动估计值，字段缺失时显示不可用。
- CPU 调度与预算属于首版控制能力；精确 FPS、GPU 配额和网络限速需另行验证。
- 管理对象是当前用户、应用 bundle 内的已验证进程。
- 同一个目标应由一个进程限制器管理，以保持暂停状态的归属。
- 真实应用的音频、远控心跳、下载与任务完成时间需按应用另行对比。
- macOS 14 和 Intel Mac 的兼容性仍需实机验证。

## 复跑

在 Xcode 中按 Command-U 运行测试。生成和检查本机应用包，在项目根目录执行：

```sh
sh Scripts/build-app.sh
python3 Scripts/check-application.py build/TaskEase.app
sh Scripts/run-self-check.sh "$PWD/build/TaskEase.app/Contents/MacOS/TaskEase"
```

测试和采样摘要保存在 `Artifacts/`。完整本机临时记录保存在 `Artifacts/local/`。
