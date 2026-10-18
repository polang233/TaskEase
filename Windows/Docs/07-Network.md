# 07 网络监控与控制

规则模型与 macOS 相同：保持联网、阻断联网、限制速度；作用时间可选仅后台或始终；仅后台时的等待时间为 0–300 秒；上下行上限分别设置，单位 KiB/s，范围 16–102400。字段和取值见 `TaskEase/Models/NetworkRule.swift`，te-model 按原样移植，`NetworkTokenBucket` 也一起移植并共享用例。

与 macOS 最大的不同在于：**Windows 上可以真正执行这些规则**，代价是需要一个以管理员权限运行的服务。

## 权限与服务

- 按应用网速、阻断和限速都需要管理员权限，由可选服务 `taskease-svc.exe`（LocalSystem）执行。
- 安装时机：用户在“设置 → 实验功能”中开启“网络功能”时，界面说明用途，用户确认后请求 UAC，注册并启动服务。关闭网络功能时，服务撤销全部规则并停止；是否同时卸载服务，在设置中提供单独的按钮。
- 服务只接受来自安装目录内 core 的连接（见 02 的 IPC 安全），并且只控制调用方用户拥有的进程。
- 界面区分三种状态，与 macOS 一致：已配置、待启用（服务未安装或未运行）、已生效（服务确认执行）。

## 按应用网速（监控）

- **来源**：服务创建实时 ETW 会话，订阅 `Microsoft-Windows-Kernel-Network` 的 TCP/UDP 发送和接收事件。事件中带有 PID 和字节数，服务按 PID 每秒汇总，推送给 core。
- core 再用完整进程身份核对成员，归入应用。基线规则与 macOS 相同：第一帧、PID 复用、计数回退或间隔超过 20 秒时重建基线，期间显示为不可用。
- **按需启停**：界面订阅网络数据时才开启会话，取消订阅后立即关闭。
- **开销**：高吞吐时事件量很大（每次收发一个事件）。V-12 需要测量 1 Gbps 下载时服务的 CPU 占用。如果超出预算，改为每秒只启用一段采样窗口，或改用 `GetPerTcpConnectionEStats`。
- **局限**：系统代为发起的流量（BITS、Delivery Optimization 等）会记在系统进程名下。界面说明沿用 macOS 文案。

## 阻断

- **技术**：WFP 用户态接口，不需要驱动。
  - 用 `FwpmEngineOpen0` 打开引擎，会话带 `FWPM_SESSION_FLAG_DYNAMIC`：会话关闭或服务崩溃时，它添加的全部过滤器由系统自动删除。这是关键的失联保护。
  - 过滤层：`FWPM_LAYER_ALE_AUTH_CONNECT_V4/V6`（出站）、`FWPM_LAYER_ALE_AUTH_RECV_ACCEPT_V4/V6`（入站），动作为 `BLOCK`。
  - 条件：
    - 非打包应用：`FWPM_CONDITION_ALE_APP_ID`，值由 `FwpmGetAppIdFromFileName0` 根据每个成员 exe 路径生成。
    - 打包应用：`FWPM_CONDITION_ALE_PACKAGE_ID`（包 SID）。
    - 两者都附加 `FWPM_CONDITION_ALE_USER_ID`，限定为调用方用户，避免影响其他用户。
  - 子层：建立 TaskEase 自己的子层，设置较高权重，过滤器统一放在这个子层下，便于整体撤销。
- **已建立的连接**：ALE 授权层只拦截新连接。阻断生效时：
  - IPv4 TCP 连接用 `SetTcpEntry(MIB_TCP_STATE_DELETE_TCB)` 主动断开（需要管理员）。
  - IPv6 TCP 没有对应的接口，只能等连接自然结束。
  - UDP 在 ALE 层按“本地端点 + 远端端点”缓存授权结果，已有的 UDP 流可能会继续通行。
  - 以上边界在界面上如实提示：“已建立的部分连接可能在断开前继续传输”。
- **解除**：删除过滤器。之后的新连接正常建立，已经断开的连接不会自动恢复，需要应用自己重连（与 macOS 文档一致）。
- **前后台切换**：后台计时到期时添加过滤器，回到前台时删除。WFP 的事务（`FwpmTransactionBegin0`/`Commit0`）可以保证一次切换是原子的。

## 限速（上下行）

- **技术**：服务内运行 WinDivert 2.2。选用 LGPLv3 许可，与 GPL-3.0-only 兼容（需要在 08 中登记）。
  - 用 `WINDIVERT_LAYER_FLOW` 获取连接与 PID 的对应关系：WinDivert 的 FLOW 层事件带有 `ProcessId`。
  - 用 `WINDIVERT_LAYER_NETWORK` 截获属于受限连接的数据包，按应用的令牌桶（每个应用上下行各一个，使用 te-model 的 `TokenBucket`）延迟后重新注入。缓冲区满时丢包，让 TCP 自行退避。
  - 过滤表达式只匹配受限应用的连接（按五元组动态更新），其他流量不进入用户态，降低开销。
- **限速精度**：存在短时突发，与 macOS 的实验记录一致，应以持续窗口的平均值验收。UDP 和 QUIC 依赖应用自身的拥塞控制，精度会差一些。
- **失联保护**：
  - core 心跳超时后，服务清空全部限速规则并直接放行。
  - 服务退出时关闭 WinDivert 句柄，驱动随之停止截获。
- **安全软件和 HVCI 兼容性**：需要验证 WinDivert 驱动在开启“内存完整性”的 Win11 上能否加载、是否被 Defender 拦截（V-11）。如果不能加载，改用下面的备选方案，下载限速暂不提供。

### 备选：基于策略的 QoS（只能限上传）

- 通过 WMI `root\StandardCimv2` 的 `MSFT_NetQosPolicySettingData` 创建策略：`AppPathNameMatchCondition` 设为 exe 文件名，`ThrottleRateAction` 设为限速值。策略存放在 ActiveStore，重启后自动消失。
- 局限：
  - 只能限制出站。
  - 按文件名匹配，同名 exe 会一起被限制。
  - 是否支持家庭版、限速是否按应用汇总计算，需要 V-11b 验证。
- 服务崩溃时不会自动撤销，需要写入恢复记录，由服务重启时清理。

## 计划下发

core 计算出“此刻每个应用应处的网络状态”，以不可变计划发给服务：

```json
{"type":"apply_network_plan","body":{
  "planVersion":42,"expiresInMs":10000,
  "apps":[{"appKey":"exe:...","members":[{"pid":1,"createTime":0,"image":"C:\\..."}],
           "mode":"block"},
          {"appKey":"pkg:...","packageSid":"S-1-15-2-...","mode":"limit","upKiBs":64,"downKiBs":256}]}}
```

- 服务以新计划整体替换旧计划，版本号必须递增。
- 计划在 `expiresInMs` 内没有续期（心跳）时，服务撤销全部规则。
- 服务回复 `plan_applied`，内容为每个应用的执行状态。界面据此区分“已配置”和“已生效”。

## 验证项

| 编号 | 内容 | 通过标准 |
| --- | --- | --- |
| V-10 | 用 WFP 动态会话阻断自建的 `testapps/net-echo`（TCP 和 UDP） | 新连接立即失败；撤销后可以重连；强制结束服务后过滤器自动消失（用 `netsh wfp show filters` 核对） |
| V-11 | 在开启内存完整性的 Win11 上，用 WinDivert 对 `net-echo` 做 64 KiB/s 双向限速 | 驱动能加载；30 秒平均速率在 ±15% 以内；结束服务后速率恢复；记录 Defender 的反应 |
| V-11b | QoS 策略备选（只在 V-11 失败时执行） | 家庭版和专业版各测一次 |
| V-12 | ETW 按应用网速的准确性和开销 | 与 net-echo 的实际字节数误差在 5% 以内；1 Gbps 下服务 CPU 不超过单核的 5% |

所有网络实验都只连接本机自建服务或用户明确提供的测试地址，不修改系统代理，不影响其他应用。
