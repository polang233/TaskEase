# 09 测试与验证

原则与 macOS 版相同：

- 构建、自动测试和实机验证分别报告。
- 历史通过记录不能代表本轮通过。
- 控制实验只使用自建的测试进程。
- 测试使用独立的数据目录，不执行用户的真实规则，也不发送真实统计。

## 测试分层

| 层 | 内容 | 位置 | 运行环境 |
| --- | --- | --- | --- |
| 单元 | Policy（组合限制取最强状态）、SamplingPolicy、BudgetCredit、TokenBucket、规则编解码与校验、应用键规范化、IPC 消息编解码 | `crates/te-model/tests` | 任意平台 |
| 共享用例 | 从 macOS 测试中提取的输入与期望输出 | `fixtures/*.json` | 任意平台 |
| 系统集成 | 进程快照、身份核对、暂停/Job/优先级、前台事件、恢复记录与 guard | `crates/te-core/tests`（标记 `#[cfg(windows)]`） | Windows |
| 自检 | `taskease-core.exe --self-check`，用测试负载做端到端验证 | 见 05 | Windows / CI |
| 服务 | WFP、WinDivert、ETW，对应 V-10 至 V-12 | `crates/te-service/tests`，需要管理员 | Windows / CI |
| 帧率 | V-08、V-09 | `testapps/` + PresentMon | Windows x64 实机或 CI |
| 界面 | 关键流程：选择应用、开启规则、切换方式、主开关、移除规则、设置、清除数据 | 用 Tauri 的 WebDriver（tauri-driver）或 WinAppDriver，按可访问名称查找 | Windows；会占用鼠标键盘，运行前先告诉用户 |
| 性能 | 01 中的性能目标 | 手动测量，结果写入 `Artifacts/local/perf-*.json` | Windows 实机 |

## 共享用例格式

```json
{
  "name": "policy-status",
  "source": "TaskEaseTests/ApplicationRulesTests.swift",
  "cases": [
    {"input": {"rule": {"enabled": true, "limitsPerformance": true, "performance": "budget", "cpuPercent": 20,
                        "adjustsVolume": false, "volumePercent": 0, "lowersPriority": false,
                        "delaySeconds": 3, "alwaysLimit": false},
               "enabled": true, "controllable": true, "isForeground": false, "isHidden": false,
               "backgroundSeconds": 2.5},
     "expect": "waiting"}
  ]
}
```

T0.2 负责从 macOS 的测试中整理以下用例：

- `policy-status.json`
- `rule-validation.json`（含旧版 `mode` 迁移与降级写入）
- `sampling-deadlines.json`
- `token-bucket.json`
- `budget-credit.json`
- `app-keys.json`（Windows 独有）

## 测试负载（testapps/）

| 程序 | 作用 |
| --- | --- |
| `cpu-burner` | 可以指定线程数与负载比例；可以派生子进程，用于验证归组和 Job 继承 |
| `windowed-app` | 带一个普通窗口，用于前台切换、最小化以及暂停后“未响应”的观察 |
| `d3d11-spinner` / `vk-spinner` | 不限帧、不开垂直同步的渲染循环，每秒打印一次帧率 |
| `tone-player` | 循环播放提示音的 WASAPI 程序，用于后台音量验证 |
| `net-echo` | 本机 TCP/UDP 回显服务和客户端，可以设定速率并统计字节数 |
| `electron-min`（V-09） | 最小的 Electron 应用，只加载本地页面 |

测试负载放在 `Windows/testapps/` 下，不打进安装包。

## 必测场景清单（对应 macOS 的验收条件）

- [ ] 没有有效规则时主开关置灰；删除最后一条有效规则后主开关自动关闭
- [ ] 系统应用默认隐藏；打开显示后仍然不可控
- [ ] 应用退出后规则保留，可以离线编辑和移除
- [ ] 前台切换、最小化、等待、关闭主开关、正常退出时，控制状态正确
- [ ] 显示刷新慢时，不会推迟控制心跳和后台等待期限
- [ ] 强制结束 core 后由 guard 恢复；强制结束 guard 后由 core 重启 guard；两者都被结束后，下次启动时补偿恢复
- [ ] 睡眠和唤醒、关机注销时，被暂停的应用先恢复
- [ ] PID 复用：恢复记录中的旧身份不会作用到新进程
- [ ] 更新和卸载前完成恢复
- [ ] 清除数据并退出：先恢复，再撤销网络规则，最后删除数据
- [ ] 服务失联 10 秒后撤销全部网络规则；WFP 过滤器随服务退出自动消失
- [ ] 帧率心跳超时后自动回到不限帧率
- [ ] 测试和预览使用夹具数据，不发送真实统计

## 证据记录

每个任务完成时，把以下内容写进 PROGRESS.md：

- 运行的命令
- 结果摘要，例如 `cargo test: 128 passed`
- 实机环境：机型或 CPU、Windows 版本号、显卡与驱动版本
- 截图或 JSON 的路径（放在 `Windows/Artifacts/local/`）

不要把用户的真实应用名称和 PID 写进会提交到仓库的文件。
