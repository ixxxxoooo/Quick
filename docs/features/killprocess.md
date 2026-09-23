# 结束进程（killprocess）

按 CPU 或内存排序列出运行中的进程，支持标题栏搜索筛选，并发送 SIGTERM / SIGKILL。

## 不变量

- **搜索框落在面板标题栏**，靠 `supportsPanelSearch == true`；内容区不再重复搜索框。
- **CPU / 内存排序切换在列表上方分段控件**，不挤在标题栏。
- **永不列出 / 结束宿主自身 PID**（`ProcessInfo.processIdentifier`）。
- **采样只在面板打开时跑**；间隔读 `killprocess.refreshInterval`，非法值回落 3 秒。
- **结束成功或失败都必须走 `ShowHUDEvent`**，并打 `QuickLog`（成功 `.notice`，失败 `.error`）。
- Model 层禁止 AppKit / SwiftUI。

## 内部结构

| 文件 | 职责 |
| --- | --- |
| `Model/ProcessRecord.swift` | 进程记录、`ps` 解析与过滤 |
| `Model/KillProcessPreferences.swift` | 设置键映射 |
| `Service/KillProcessService.swift` | 刷新与 `kill(2)` |
| `UI/KillProcessView.swift` | 列表 + 排序切换 + 结束动作 |

## 持久化

| 键 | 含义 | 默认 |
| --- | --- | --- |
| `killprocess.sortMode` | `cpu` / `memory` | `cpu` |
| `killprocess.refreshInterval` | 刷新秒数 | 3 |
| `killprocess.showPID` | 显示 PID | false |
| `killprocess.searchInPath` | 搜索匹配路径 | false |
| `killprocess.searchInPID` | 搜索匹配 PID | false |

## 已知限制

- 受保护的系统进程可能结束失败（权限不足），HUD 会提示。
- 未实现 Raycast 的「结束后关窗 / 清搜索 / 回根搜索」选项。
