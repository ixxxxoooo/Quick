# 系统监控（sysmonitor）

对齐 [Raycast System Monitor](https://www.raycast.com/hossammourad/raycast-system-monitor)：
左侧切换 System Info / CPU / Memory / Disk / Power / Network，右侧展示明细与高占用进程。

## 不变量

- **采样只在面板打开时跑。** `SystemMonitorView.task` 驱动 `ProcessScanner.startSampling()`；
  面板关掉任务取消，后台不空转。
- **采样间隔每轮重读设置键**（`PluginSettingKey.SystemMonitor.interval`），非法值回落 2 秒；
  不允许 0（忙等）。
- **内存口径与活动监视器 / Raycast 一致**：
  `used = (pageable_internal - purgeable) + wired + compressor`（页 × pagesize → MB）。
- **显示模式（已用 / 空闲）只影响展示，不改变采集。** 侧栏百分比按
  `UsageDisplayMode` 翻转；压力色阶按「资源紧张度」算（空闲模式压力 = 100 − 展示值）。
- **默认标签来自设置键 `sysmonitor.defaultTab`**，非法值回落 `system-info`。
- **硬件信息用 `system_profiler` 读一次后缓存**，不在每轮采样里重复拉。
- **无内置电池的机型（台式）电源侧栏必须显示 `N/A`**，不能伪造电量。
- **温度**：优先 IOHID 传感器读数；若机型未暴露传感器，侧栏/详情仍展示
  `ProcessInfo.thermalState`（系统热压力），不得空白。
- **Model 层禁止 AppKit / SwiftUI**；Mach / ifaddrs / `Process` / HID `dlsym` 只出现在 `Service/`。
- **序列号会出现在系统信息页**；复制系统报告前应提醒用户（与 Raycast 隐私说明一致）。
- **侧栏不提供搜索框**；六个（含温度共七个）分类直接列出。

## 内部结构

| 文件 | 职责 |
| --- | --- |
| `Model/SystemMonitorTab.swift` | 侧栏六个视图 + 显示口径枚举 |
| `Model/SystemMonitorPreferences.swift` | 设置键 → 安全默认值 |
| `Model/SystemMetrics.swift` | 格式化与压力色阶 |
| `Model/ProcessListing.swift` | `ps` 输出解析（含 RSS） |
| `Model/*Parsing.swift` / `CpuLoad.swift` | 各模块纯解析 |
| `Service/ProcessScanner.swift` | 采样编排与可变状态 |
| `Service/CpuHostSampler.swift` | Mach CPU tick |
| `Service/NetworkInterfaceSampler.swift` | ifaddrs 接口与计数器 |
| `UI/SystemMonitorView.swift` | 双栏外壳 + 侧栏摘要色 |
| `UI/SystemMonitorDetailViews.swift` | 各标签明细 |

## 持久化

| 键 | 含义 | 默认 |
| --- | --- | --- |
| `sysmonitor.interval` | 采样秒数（1/2/5/10） | 2 |
| `sysmonitor.defaultTab` | 打开时选中的标签 | `system-info` |
| `sysmonitor.displayModeCPU` | CPU 已用/空闲 | `used` |
| `sysmonitor.displayModeMemory` | 内存已用/空闲 | `used` |
| `sysmonitor.displayModeDisk` | 磁盘已用/空闲 | `free` |
| `sysmonitor.displayModeBattery` | 电池已用/空闲 | `free` |
| `sysmonitor.showMenuBarStats` | 菜单栏文案（未接线） | false |

## 已知限制

- 菜单栏 CPU/内存文案开关仍是占位，未接到 `NSStatusItem`。
- 未移植风扇转速（Raycast 依赖私有 SMC 工具）。
- 部分机型 IOHID 温度传感器为空时，仅能看到系统热压力等级。
- 网络吞吐需要至少两帧采样才有速率；首轮侧栏显示 `—`。
- 「打开活动监视器」固定打开应用，不按当前标签跳到对应页签。
