# 日志规范

本项目的硬性要求：**所有代码、所有功能都要有完善的日志。**
目标是出问题时能只靠日志定位原因，不需要用户重现、不需要加断点。

---

## 1. 统一入口：`QuickLog`

**禁止裸 `print`。** 全仓不允许出现 `print(`、`NSLog(`、`dump(`；统一走 `QuickLog`，
它封装了 `os.Logger`，日志会进统一日志系统（Console.app / `log stream`），
带子系统、分类、时间戳与级别，可过滤、可持久化。

```swift
import QuickCore

// 模块：用模块自己的 id 作为分类
private let log = QuickLog.module(ClipboardModule.id)

// 应用/框架层：用固定区域名
private let log = QuickLog.palette
```

子系统取自 `Bundle.main.bundleIdentifier`：

| 渠道 | Bundle ID | 看日志 |
| --- | --- | --- |
| Release / 已安装 | `com.ygw.quick` | `./Scripts/logs.sh` |
| Debug（本地） | `com.ygw.quick.dev` | `./Scripts/logs.sh --dev` |

详见 [development.md#发布](development.md)。

---

## 2. 五档级别，用法是固定的

**关键约束：`debug` 和 `info` 不写入磁盘。** `log show` 事后读不到它们，
只有 `notice` 及以上才会持久化。所以：

- **要求「事后能靠日志排查」的东西，必须用 `.notice` 或更高。**
- `.debug` / `.info` 是给「实时跟踪 + 开发期」看的，用 `Scripts/logs.sh` 抓。

判断标准有两条，都要过：

1. **这条日志需要在问题发生之后、翻历史时读到吗？** 需要 → `notice` 及以上。
2. **它在生产环境每秒可能打十次吗？** 会 → `debug`。

| 级别 | 何时用 | 落盘？ | 事后可查？ |
| --- | --- | --- | --- |
| `.debug` | 开发期细节：每次按键、每行渲染、循环内部 | 否 | 否 |
| `.info` | 实时观察用的中间状态：面板显隐耗时、搜索耗时 | 否 | 否 |
| `.notice` | **生命周期与状态变化**：应用启停、模块激活、快捷键注册结果、扫描结果、权限授予、设置改动 | **是** | **是** |
| `.warning` | 可恢复的问题：某模块降级、图标缺失、取消订阅无效 | 是 | 是 |
| `.error` | 操作失败且用户会受影响：写盘失败、注册快捷键失败、外部命令非零退出 | 是 | 是 |
| `.fault` | 编程错误 / 状态不可信：不变量被打破 | 是 | 是 |

一句话记忆：**要能事后查的写 `notice`，只在实时看细节的写 `debug`/`info`。**

---

## 3. 必须打日志的位置（清单）

写新功能时逐条对照，一项都不能漏：

**生命周期**
- 应用启动的每个关键阶段：启动开始/完成、模块注册完成（打了几个）、事件总线接线条数。
- 模块 `activate()` / `deactivate()`，以及加载了多少条持久化数据（`.notice`）。
- 应用扫描完成：条目数、去重后条目数、耗时（`.notice`）。
- `AppCore.prepareForTermination()` 的退出路径。

**系统交互**
- 全局快捷键：注册成功（含具体组合键，`.notice`）、注册失败（含 `OSStatus` 原始值，`.error`）、注销。
- 权限：检查结果、申请发起、申请结果（授予/拒绝）。
- 外部命令 / `NSTask`：命令名与参数（脱敏后）、退出码、耗时。非零退出必须是 `.error`。
- 网络请求：URL 主机（**不要打完整 query**）、状态码、耗时。失败必须带错误描述。

**持久化**
- 读取失败、解码失败、写入失败 —— 全部 `.error`，并带上文件路径与错误描述。
- 数据加载成功时的条数 —— `.notice`（用户说「我的历史空了」时，这是第一手证据）。
- 数据迁移、格式版本升级 —— `.notice`。

**状态与错误**
- 每个 `catch` 分支至少一条日志。**空 `catch` 是不可接受的。**
- 状态机的迁移（面板显示/隐藏、模块切换、模式切换）—— `.info`。
- 不变量被打破 —— `.fault`。

**性能敏感路径**
- 面板显隐耗时（`show()` 到可见）—— `.info` + signpost。
- 一次聚合搜索：耗时、参与模块数、命中条数 —— `.debug`（高频）+ signpost。
- 应用扫描 / 文件索引：条目数、耗时 —— `.notice` + signpost。

---

## 4. 性能测量用 `signpost`，不要用 `info`

需要量化耗时的地方用 signpost，它会出现在 Instruments 里，开销近乎为零：

```swift
let signpost = QuickLog.signposter(category: "launcher")
let id = signpost.begin("AppIndex.refresh")
defer { signpost.end("AppIndex.refresh", id: id) }
```

- 面板显隐、聚合搜索、应用扫描、文件索引、网络请求都必须有 signpost 区间。
- 不要在热路径里用 `Date()` 手算耗时再打 `.info` —— 那既慢又没法和 Instruments 对齐。

---

## 5. 结构化字段

`os.Logger` 支持保留类型的字段，它比字符串拼接更可读、可过滤、在 Console 里可展开：

```swift
// ✅ 字段保留类型
log.info("面板已显示，耗时 \(elapsed, format: .fixed(precision: 1)) ms，屏幕 \(screenName, privacy: .public)")

// ❌ 手工拼字符串
log.info("面板已显示，耗时 " + String(elapsed) + " ms")
```

- 数字用 `format:` 指定精度。
- 可能含用户信息的字符串标 `privacy: .private`（默认就是 private）。
- 需要能在 Console 里直接看到值的（模块 id、状态名、错误码）标 `privacy: .public`。

---

## 6. 隐私红线

日志会落在磁盘上并可能被收集，所以以下内容**永远不进日志**：

- 剪贴板正文、笔记正文、代码片段内容、AI 对话内容、翻译原文。
  → 只记**长度**或**类型**：`log.debug("剪贴板新增条目，类型 \(kind, privacy: .public)，\(text.count) 字符")`
- 密码、令牌、API Key。
- 完整的用户文件路径（记最后一段或数量即可，除非路径本身就是排错必需）。
- 搜索结果的具体内容（记条数即可）。

---

## 7. 反例

```swift
// ❌ 裸 print —— 不进统一日志，没有级别，没有分类，生产环境抓不到
print("[Clipboard] 已保存")

// ❌ 空 catch —— 出了问题什么都看不到
do { try store.save() } catch {}

// ❌ 高频 debug 打成 info —— 每次按键都写盘，日志变性能问题
log.info("搜索关键词: \(query)")

// ❌ 记录隐私内容
log.info("复制文本: \(clipboardText)")

// ❌ 自己拼时间戳 —— 统一日志已经有时间戳了
print("\(Date()) 面板已显示")

// ✅ 正确的样子
log.info("模块已激活，加载 \(entries.count, privacy: .public) 条历史")
log.error("写入失败: \(url.lastPathComponent, privacy: .public) — \(error.localizedDescription, privacy: .public)")
log.debug("搜索完成，命中 \(results.count, privacy: .public) 条")
```

---

## 8. 查看日志

```bash
./Scripts/logs.sh                  # 实时跟踪全部（含 debug —— 排障首选）
./Scripts/logs.sh --errors         # 近 1 小时的 warning / error / fault
./Scripts/logs.sh --saved          # 已落盘的历史（notice 及以上）
./Scripts/logs.sh -c palette       # 只看面板这个分类
./Scripts/logs.sh -c module.clipboard   # 只看剪贴板模块
```

底层命令（脚本已处理「用户 shell 可能覆盖 `log`」的问题，手动敲时注意用绝对路径）：

```bash
/usr/bin/log stream --predicate 'subsystem == "com.ygw.quick"' --level debug --style compact
/usr/bin/log stream --predicate 'subsystem == "com.ygw.quick" AND category == "module.clipboard"' --level debug
/usr/bin/log show --predicate 'subsystem == "com.ygw.quick" AND messageType >= warning' --last 1h --style compact
```

**再强调一次**：`log show` 读的是磁盘上的持久化日志，`debug` 与 `info` 不在其中。
「刚才面板为什么没弹出来」这类问题要用 `log stream` 复现着看，或者看已经落盘的
`notice`/`error`。
