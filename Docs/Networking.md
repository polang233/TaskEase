# 应用网络监控与规则

## 使用流程

在应用管理中选择应用，查看接收和发送速度。在“应用与进程信息”展开后查看各个自有进程的速度。设置中的“显示应用网络速度”控制是否采集和显示网络计数。

在“网络规则”选择保持联网、阻断联网或限制速度。规则可配置仅后台或始终作用；仅后台支持 0 至 300 秒等待时间。上下行上限分别设置，单位为 KiB/s，范围 16 至 102400。

网络规则进入“已配置规则”列表，应用退出后仍可编辑。移除网络规则保留 CPU 规则；应用标题的移除按钮删除该应用的全部规则。顶部后台限制开关控制 CPU 规则。

当前构建提供网络监控和网络规则配置。阻断与限速配置显示“待启用网络扩展”，可保存参数；实际网络控制需要签名的 Network Extension 与用户的系统批准。

## 结构与职责

| 模块 | 职责 |
| --- | --- |
| Models/NetworkReading | 字节计数、速度、采样状态 |
| Models/NetworkRule | 网络模式、作用时间、上限和纯策略 |
| Services/Networking/NetworkMonitor | 限时系统快照进程及取消 |
| Services/Networking/NetworkCounters | CSV 边界解析、完整进程身份基线和速度合计 |
| Services/Monitoring/ProcessMonitor | 应用分组、成员校验及网络结果合并 |
| App/AppModel | 配置持久化、显示需求、规则列表与错误状态 |
| Features/Networking/NetworkRuleEditor | 网络规则编辑与能力提示 |

网络配置使用独立的 networkRules.v1。CPU 的 rules.v1 保持原有格式。名称与应用路径复用 ruleApplications.v1，列表展示两个规则集合的并集。读取损坏的网络配置时保留备份，不改变 CPU 规则的启用状态。

## 监控数据

调用 macOS 自带 nettop 的进程汇总模式，关闭地址解析，仅请求 bytes_in 和 bytes_out。读取系统汇总后，筛选当前已验证应用的进程成员。采样只处理进程标识与字节计数，不解析或保存通信内容、目标地址。

读取前由 libproc 建立 PID、UID、启动时间和应用归属，读取后再次核对身份。速度基线以完整 ProcessIdentity 为键。第一帧、PID 复用、计数回退和超过 20 秒的间隔重建基线，以不可用表示尚未形成有效速度。

同一应用的主进程和自有辅助进程合计。系统代发、共享代理、应用包之外的服务，以及采样间隔内出现和结束的短连接可能无法准确归属。界面数据表示系统进程计数的变化，不作为完整流量账单。

数据面板无需刷新或用户关闭网络显示时取消读取，不启动周期网络任务。单次读取限时 1.5 秒、输出上限 1 MiB；只结束本工具创建且身份仍匹配的进程。输出使用匿名文件描述符，正常完成及进程退出后释放。CPU 控制采样与网络显示采样分离，读取失败时 CPU 和内存继续更新。

异步读取未完成时，显示定时器按正常间隔等待，控制心跳和后台等待期限仍取最早期限，避免过期显示时间引起频繁唤醒。

## 网络控制的后续实现

网络控制应独立于 CPU 工作进程。CPU 暂停会影响整个进程，网络规则应通过系统提供的流量接口实施。

| 方案 | 适用能力 | 验证重点 |
| --- | --- | --- |
| Content Filter 系统扩展 | 应用流量允许与阻断 | 应用身份、已有连接、规则更新和取消 |
| Transparent Proxy 系统扩展 | TCP/UDP 流量转发与速度控制 | DNS、UDP/QUIC、背压、缓冲上限和代理兼容 |

阻断优先采用 NEFilterDataProvider。macOS 通过 sourceAppAuditToken 与 sourceProcessAuditToken 提供来源信息，应结合 Security 的签名信息、当前用户和应用归属验证，区分系统代表应用发起的连接。iOS 的 sourceAppIdentifier 不适用于 macOS。

速度控制以整个应用为额度归属，上下行各有独立额度。NetworkTokenBucket 已提供可独立验证的额度计算，控制适配器后续使用这份策略。限速存在短时突发，应以持续窗口验证平均值。

Content Filter 支持暂停和恢复流，但 UDP 暂停超过 10 秒会被系统丢弃。完整上下行限速需要验证透明代理的背压与 UDP 数据报调度，不能将 TCP 的暂停策略直接作为 UDP 的可靠限速保证。

主应用持有用户配置和前后台状态，系统扩展持有实际流量执行状态。规则更新使用有版本的不可变计划，并包含有效期。主应用退出、计划失效、睡眠或用户关闭控制时恢复允许状态。系统扩展在规则安装与执行确认前，界面保持待启用状态。

被阻断的连接可能已经失败；解除规则允许后续重连，不能承诺恢复已经关闭的连接。验证应先使用自建 TCP/UDP 流量，再检查远控、下载和现有代理软件。

签名阶段需要 Apple Developer Program 团队、相应 Network Extension 能力、同团队的宿主与系统扩展、预置描述文件和本机系统批准。当前主应用保持普通版本的签名与权限，不自动安装网络过滤器。

## 验证

自动验证覆盖字段顺序、带逗号的进程名、多目标快照、应用成员合计、进程身份变化、计数回退、空闲基线、独立规则存储、离线编辑、速率额度和待启用状态。界面验证覆盖网络规则保存、作用时间、限速输入与移除。

真实只读快照在本机读取到 11 个应用，其中 7 个有可归属的网络计数和速度。原始应用名称与 PID 不写入公开摘要。资源验证同时记录主进程与已退出的读取子进程 CPU，避免忽略网络读取工具的开销。

## 参考

- [Apple Content filter providers](https://developer.apple.com/documentation/networkextension/content-filter-providers)
- [Apple Network Extension 部署方式](https://developer.apple.com/documentation/technotes/tn3134-network-extension-provider-deployment)
- [Apple Handling Flow Copying](https://developer.apple.com/documentation/networkextension/handling-flow-copying)
- [Apple resumeFlow](https://developer.apple.com/documentation/networkextension/nefilterdataprovider/resumeflow(_:with:))
- 本机 SDK 的 NEFilterDataProvider.h、NEFilterFlow.h 和 sys/resource.h；nettop -h。
