# Quick 架构重构方案

> 本文是 2026-09 一次静态架构审计的结论与执行计划。
> 审计方式：**只读代码**（约 9.6 万行 Swift、31 个 SPM 包），
> 未编译、未运行。凡涉及「实际有多慢」的判断都在文中标注了 `[需实测]`。
> 本文与 [`AGENTS.md`](../AGENTS.md) 的既有规则不冲突；若冲突以 `AGENTS.md` 为准。

## 结论摘要

架构方向是对的，**问题在于契约比实现诚实**：文档描述的是一套现代体系，
代码里有大量 legacy 残留、隐式字符串协议与主 actor 瓶颈在背离它。

具体地：

- **方向正确的部分**（重构中不碰）：`AppCore` 单一所有者、插件只在 `registerPlugins()`
  实例化、`CommandIndex` 的「建索引预处理 + 按键只打分」、`DesignTokens` 单一令牌源、
  `QuickLog` 分级体系、插件自治 SQLite schema。
- **需要修的部分**：协议里的 SwiftUI 耦合、搜索管线的并发模型、退化成公开可变闭包的
  依赖注入、遗留 API 与死代码、设置页长在共享包里。

**最大单项收益是 Phase 2（搜索管线）**，因为它同时解决「超时杀不掉」「2 秒卡住整批结果」
「线性扫描命令归属」三个问题。

---

## Phase 0：清僵尸与死代码

**风险：零。收益：立刻可验证。前置：无。**

### 0.1 删除本地僵尸包目录

`Packages/PluginWeather`、`Packages/PluginWindowManager`、`Packages/PluginWordCounter`
只有 `.build/` 与 `.swiftpm/`，**没有任何源码、没有 `Package.swift`，且未被 git 跟踪**。

```bash
rm -rf Packages/PluginWeather Packages/PluginWindowManager Packages/PluginWordCounter
```

验收：`ls Packages/` 输出 28 项（3 核心 + 25 插件）。

### 0.2 删除死代码：`Base64CodecPlugin.searchItems`

该方法的实现在当前代码路径下**永远不会被调用**：

- `accepts(query:)` 用协议默认实现 → 恒为 `false` → 聚合器不调 `dynamicSearch`；
- `commands` 里没有对应 `CommandDescriptor` → 静态索引里也没有它。

同类的还有 `ColorCompare`、`HashCalculator`、`JSONFormatter`、`KillProcess`、
`MarkdownPreview`、`NetworkTools`、`SQLFormatter`、`SystemMonitor`、`TextDiff`、
`TimestampConverter`、`URLCodec`、`UUIDGenerator` —— 这些插件的 `searchItems`
都只是「触发词 → 一条导航条目」，而这正是 `commands` 默认实现已经提供的能力。

**处理原则（逐个判定，不要一刀切）：**

| 情况 | 处理 |
|---|---|
| 只返回一条「打开本插件」 | **删**，`commands` 默认实现已覆盖 |
| 是插件动态搜索的**唯一实现体**（如 Clipboard、Notes、Launcher） | **改名**为私有函数，如 `private func searchEntryPoints(query:)`，由 `dynamicSearch` 调用 |
| 部分转发 + 部分额外逻辑 | 拆开：额外逻辑留在私有函数，转发部分删 |

验收：

```bash
grep -rn "func searchItems" Packages/*/Sources/ | grep -v "QuickCore/Sources"
# 期望：无输出
```

### 0.3 删除 `defaultItems()`

全仓只有一个实现者（`LauncherPlugin`）和一个调用点（协议默认实现内部）。

1. 删 `QuickPlugin.defaultItems()` 与默认实现；
2. `LauncherPlugin.defaultItems()` 的逻辑若仍需首屏露出，改走
   `CommandDescriptor.showsWhenQueryEmpty`；
3. 删 `LauncherPlugin` 里的覆写。

验收：`grep -rn "defaultItems" Packages/ Quick/` 无输出。

### 0.4 修正违规的 `@unchecked Sendable`

`Packages/PluginCalculator/Sources/PluginCalculator/Model/CalcEngine.swift:308`
的 `final class MathParser: @unchecked Sendable` 违反项目红线
（唯一允许的例外是 Carbon C 回调跳板）。

改用 `Mutex`（`Synchronization`，项目已在 `EventBus` 里用过）保护可变状态，
或把可变状态移出该类型。验收：`grep -rn "@unchecked Sendable" Packages/PluginCalculator/` 无输出。

---

## Phase 1：把 UI 从核心契约里拿出来

**风险：中（改动面广）。收益：核心层可脱离 SwiftUI 编译，视图身份可保留。**

### 1.1 问题

```swift
// QuickCore/Sources/QuickCore/Protocols/QuickPlugin.swift
import SwiftUI   // ← 核心层被 UI 框架污染

public protocol QuickPlugin: AnyObject, Sendable {
    func makeView() -> AnyView
    func makeSettingsView() -> AnyView?
}
```

两个后果：

1. `QuickCore` 为了两个方法引入整个 SwiftUI；`SearchableItem` 也 `import SwiftUI`，
   而它实际只需要 `Foundation`。
2. `AnyView` 抹掉视图身份（view identity）。`PaletteRootView` 每次重建都走动态派发，
   在按键级刷新的面板里是实打实的开销。`[需实测]` 具体数值要用 Instruments 量。

### 1.2 方案

**`QuickCore` 侧：** 删掉 `makeView()` / `makeSettingsView()`，去掉 `import SwiftUI`。

**`QuickUI` 侧：** 新增能力协议，由插件包实现（插件依赖 `QuickUI` 是允许的方向）：

```swift
// Packages/QuickUI/Sources/QuickUI/Panel/PluginViewProviding.swift

/// 插件为自己的面板提供根视图
///
/// 与 `QuickPlugin` 分开，是为了让 `QuickCore` 不必认识 SwiftUI。
@MainActor
public protocol PluginViewProviding {
    func makeView() -> AnyView
}

/// 插件为自己的设置页提供内容
@MainActor
public protocol PluginSettingsProviding {
    func makeSettingsView() -> AnyView?
}
```

**宿主侧取值改为运行时能力查询：**

```swift
// AppCore / PaletteCoordinator 里
let view = (plugin as? PluginViewProviding)?.makeView()
```

需要留意的取舍：能力查询是运行时判定，`as?` 失败时**必须打 `.warning` 日志**
（照 `PaletteCoordinator.makePluginView` 现有做法），否则「插件忘了实现协议」
会表现成面板一片空白。

### 1.3 顺带修正 `SearchableItem` 的 `Hashable`

当前 `==` 与 `hash` **只看 `id`**，但 `Equatable` 的语义要求「相等的两个值行为一致」——
两个 id 相同而 `action` 不同的条目会被判等，`ForEach` 与去重都建立在这个可疑前提上。
这与 Phase 2 的「去重」逻辑直接相关。

建议：保留「id 去重」这一业务语义，但**不要通过 `Equatable` 表达**。
把去重逻辑显式化（`PaletteSearchEngine` 已经有 `seen` 集合做这件事了），
`Hashable` 改为合成实现或直接删掉 `Hashable` 一致性。

验收：

```bash
grep -rn "import SwiftUI\|import AppKit\|import Cocoa" Packages/QuickCore/Sources/
# 期望：无输出（QuickCore 彻底不依赖 UI 框架）
```

---

## Phase 2：搜索管线重构（最大收益）

**风险：高（改所有插件签名）。收益：最大。前置：Phase 1。**

### 2.1 问题一：主 actor 瓶颈让「并发 + 超时」形同虚设

```swift
// Packages/QuickUI/Sources/QuickUI/Panel/PaletteSearchEngine.swift
group.addTask {
    await plugin.dynamicSearch(query: query)   // plugin 是 @MainActor
}
group.addTask {
    try? await Task.sleep(for: pluginTimeout)  // 2 秒
    return nil
}
```

`withTaskGroup` 只让任务**并发排队**；`dynamicSearch` 整体在主 actor 上执行，
CPU 密集或同步阻塞的实现仍然串行占着主线程。超时后 `group.cancelAll()` 只是
放弃等待，**杀不掉已经在跑的同步代码**——只有插件内部显式检查 `Task.isCancelled`
才可能提前退出。

且超时结果是 `return []`，不报错：用户看到「没找到」，实际是「搜索超时了」。

`[需实测]` 量化方式：`PaletteSearchEngine` 已有 `elapsedMS > 50` 的 warning 分支，
统计它的占比即可。若占比 < 1%，本项优先级可下调。

### 2.2 方案：`dynamicSearch` 标 `nonisolated`

方向已确认采用**改协议**（而非宿主侧自旋等待的过渡层）。

```swift
public protocol QuickPlugin: AnyObject, Sendable {
    /// 这次查询要不要走动态搜索
    ///
    /// **必须 nonisolated 且便宜**：它在每次按键、每个已启用插件上都要跑，
    /// 不允许碰主 actor 状态。
    nonisolated func accepts(query: String) -> Bool

    /// 按查询现算的结果
    ///
    /// **必须 nonisolated**：实现里不许碰主 actor 隔离的状态。
    /// 需要在主 actor 上读取的数据（设置、缓存快照）要在调用前取出并作为参数传入，
    /// 或在此返回 Sendable 的结果由调用方合并。
    nonisolated func dynamicSearch(query: String) async -> [SearchableItem]
}
```

**迁移每个插件时的固定套路：**

1. `accepts` 只读 `static` 常量与 `Sendable` 快照 —— 通常不用改；
2. `dynamicSearch` 内部若读实例状态（store、缓存），把该状态改为 `let` +
   `Sendable`，或在插件初始化时快照成不可变值；
3. 真需要 IO 的实现用 `Task.detached` 或 `nonisolated` 函数直接跑。

**明确不做的事**：不引入第二个 actor（项目规矩：只有「主 actor」与「无隔离」两档）。

### 2.3 问题二：超时不可见

超时不能静默返回空数组。方案：`PaletteSearchEngine.search` 返回结果集时
附带被超时的插件 id 列表，由 `PaletteRootView` 决定是否在底部提示
（如「3 个插件未及时返回」）。若改动过大，最低限度是超时时发
`ShowHUDEvent(message: "部分插件搜索超时", tone: .warning)`。

### 2.4 问题三：`plugin(forCommand:)` 线性扫描

```swift
// Quick/AppCore.swift
private func plugin(forCommand commandID: String) -> (any QuickPlugin)? {
    if let owner = plugins.first(where: { type(of: $0).commands.contains { $0.id == commandID } }) {
        return owner
    }
    return plugins.first { commandID.hasPrefix(type(of: $0).id + ".") }
}
```

按「插件数 × 命令数」线性扫描，每次 `perform` 都重算。而 `rebuildCommandCatalog()`
**已经把命令快照成 `[IndexedCommand]`，却从没用它做过 id → owner 查找**。

方案：建索引并在 `rebuildCommandCatalog()` 时一并重建。

```swift
/// 命令 id → 插件 id
private var commandOwners: [String: String] = [:]

/// 插件 id → 插件实例
private var pluginsByID: [String: any QuickPlugin] = [:]
```

`AppCore` 里另外 5 处线性扫描（`resolveRecentItem`、`resolveRecentItem` 的 commands 分支、
`detachPlugin`、`invoke`、`syncPaletteMode`、`makePluginView`）全部改用 `pluginsByID`。

### 2.5 问题四：触发词跨插件冲突无人仲裁

`matchesAnyTrigger` 是**子串**匹配，而多个插件声明了同一批通用词：

| 触发词 | 声明它的插件 |
|---|---|
| `编码` / `解码` | Base64Codec、URLCodec |
| `格式化` | JSONFormatter、SQLFormatter |
| `查询` | NetworkTools |
| `生成` | UUIDGenerator |
| `对比` | TextDiff、ColorCompare |

（`"对比"` 见 `PluginTextDiff.triggerWords`、`"对比度"` 见 `PluginColorCompare.triggerWords`）

输入「编码」时两套编解码器同时 `accepts` 返回真，两批结果一起涌进面板。
`docs/features.md` 写了「精确匹配到两条时不执行」，但 `accepts`/`dynamicSearch`
里**没有任何仲裁代码**。

方案：把「多插件命中同一触发词」当成一个显式设计决策，三选一：

- **A（推荐）**：触发词唯一性由测试保证 —— 加一条测试扫描所有插件的
  `triggerWords`，发现跨插件重复即失败。通用词（`编码`/`格式化`）从插件里删掉，
  改由 `CommandDescriptor.keywords` 承载（命令级关键词可以重复，因为
  `CommandIndex` 会按相关度统一排序，不存在「两个插件各自铺满结果」的问题）。
- **B**：保留冲突，但在聚合层做仲裁：同一触发词命中多个插件时，只保留相关度最高的
  一个插件的结果集。
- **C**：把触发词从「子串匹配」改成「前缀匹配」。

建议 A + 在 `CommandDescriptor.keywords` 里保留通用词。

### 2.6 Phase 2 验收

- `./Scripts/run-tests.sh` 全绿；
- 面板 `show()` → 可见 < 100 ms、按键 → 结果 < 50 ms，**有实测数据**
  （用现成 signpost 日志，不要只靠肉眼）；
- `elapsedMS > 50` 的 warning 占比 `[需实测]` 降到 1% 以下；
- `grep -rn "func dynamicSearch" Packages/Plugin*/Sources/ | grep -v nonisolated` 无输出。

---

## Phase 3：依赖注入替代公开可变闭包

**风险：中。收益：消灭「漏设一个参数就静默降级」这类 bug。**

### 3.1 问题

`PaletteCoordinator` 暴露 8 个 `public var`：`invokeCommand`、`isSearchSourceEnabled`、
`onDetach`、`onPanelWillShow`、`onPanelDidHide`、`usageHistory`、`staticCommands`、
`onPanelDidHide`。后果：

- 初始化顺序成为**隐式契约**。漏设 `isSearchSourceEnabled` 不报错，
  默认 `{ _ in true }` 静默放行所有插件；
- 无法在测试里构造一个「接线完整」的协调器；
- 该类同时承担窗口生命周期、全局事件监视器、搜索聚合、插件视图工厂、
  剪贴板时间戳 5 类职责（613 行）。

### 3.2 方案

**第一步：不可变注入结构。**

```swift
/// 面板协调器的全部外部依赖
///
/// 一次性传入，之后不再变更：把「漏设一个参数就静默降级」变成编译错误。
@MainActor
public struct PaletteDependencies {
    public let invokeCommand: (String) -> Void
    public let isSearchSourceEnabled: (String) -> Bool
    public let onDetach: (String) -> Void
    public let usageHistory: UsageHistory?
    public let onPanelWillShow: () -> Void
    public let onPanelDidHide: () -> Void
}
```

`public var` 收敛为 `private let`，初始化器接收 `PaletteDependencies`。
注册时机问题（`plugins` 在 `start()` 里才注入）用一个显式的
`func attach(plugins:)` 处理，并在未 attach 时打 `.warning` 而非静默空数组。

**第二步：按职责拆成三个类型。**

| 新类型 | 职责 | 从现 `PaletteCoordinator` 搬走的部分 |
|---|---|---|
| `PaletteWindowController` | 窗口生命周期、定位、缩放、焦点、外部点击监视 | `ensurePanel`、`presentPanel`、`hide`、`positionOnCursorScreen`、`applyPaletteMetrics`、`observeOutsideClicks` |
| `PaletteSearchController` | 搜索快照、聚合调用、命令执行路由 | `staticCommands`、`search(query:)`、`routeMove/routeSubmit/routeTab` |
| `PalettePresenter` | 模式切换、导航、Esc 语义 | `navigate`、`popToRoot`、`handleEscape`、`syncPaletteMode` |

保持 `PaletteCoordinator` 作为对外的门面（`show`/`hide`/`toggle`），
内部委托给三者——这样 `AppCore` 的调用点不用大改，降低这次重构的风险面。

**注意（保留现有约束）**：拆分后**仍然不要给任何被 SwiftUI 观察的类型加 `@Observable`**。
`PaletteCoordinator` 顶部的注释说明了原因（与 `AttributeGraph` 形成重建死循环）。
`PaletteSelection` / `PaletteQuery` / `PaletteMode` 作为纯状态持有者可以继续被观察。

### 3.3 Phase 3 验收

- `PaletteCoordinator` 不再有 `public var`（除纯状态持有者）；
- 新增测试：构造 `PaletteDependencies` 的 mock，验证 Esc 三层优先级、
  导航、搜索路由的纯逻辑分支；
- 面板显隐、上下键、回车、Esc 冒烟全部通过。

---

## Phase 4：插件设置页下沉

**风险：中高（机械改动多）。收益：依赖方向摆正。**

### 4.1 问题

`Packages/QuickUI/Sources/QuickUI/Windows/Settings/Panes/FeatureSettingsPanes.swift`
共 **1079 行**，通过 `SettingsDataSource.makeFeatureSettingsView(for:)` 集中分发
（`SettingsBridge.swift:443` 是唯一实现）。

后果：**每个插件的 UI 都长在共享包里**。给某个插件加一个设置项，要去改 `QuickUI`——
依赖方向在这里是反的（`QuickUI` 不该认识任何插件的专属配置）。

同时 `SettingsDataSource` 协议有 **30+ 个方法**，全部由 `SettingsBridge` 一个类实现，
是典型的 God Protocol。

### 4.2 方案

**第一步：插件侧提供设置内容。**

插件实现 Phase 1 引入的 `PluginSettingsProviding`，设置视图放在插件自己的包里。

**第二步：`QuickUI` 只留容器与组件。**

`FeatureSettingsPane` 保留三块结构（概览 / 专属配置 / 触发关键字），
但「专属配置」改为调用注入的 provider 闭包，不再 switch 插件 id。

**第三步：拆 `SettingsDataSource`。**

按现有 `// MARK:` 分组拆成 4 个协议，各自单一职责：

| 协议 | 方法组 |
|---|---|
| `GeneralSettingsDataSource` | 通用、启动项、热键 |
| `LauncherSettingsDataSource` | 应用与搜索范围、系统操作、Shell 与自定义命令 |
| `PluginSettingsDataSource` | 插件开关、命令开关、别名、搜索来源 |
| `SuperPanelSettingsDataSource` | 超级面板偏好 |

`SettingsBridge` 继续实现全部四个（组合优于继承），但每个设置页只依赖它需要的那一个。

### 4.3 Phase 4 验收

- `FeatureSettingsPanes.swift` < 250 行（符合 `AGENTS.md` 的单视图文件上限）；
- `grep -n "case \"" Packages/QuickUI/Sources/QuickUI/Windows/Settings/` 无插件 id 硬编码；
- 每个设置页仍能打开、读写偏好、明暗两模式视觉无回归。

---

## Phase 5：并发与测试补齐

**风险：低。收益：长期。**

### 5.1 测试覆盖断崖

| 包 | 源码 | 测试 | 测试率 |
|---|---|---|---|
| `PluginScreenshot` | 2,390 | 205 | **8.6%** |
| `PluginJSONFormatter` | 1,109 | 173 | **15.6%** |
| `PluginCalculator` | 1,179 | 355 | 30% |
| `QuickUI` | 15,447 | 2,233 | 14%（含 577 行 `PluginPanelControllerTests`） |

优先补 `PluginScreenshot` 与 `PluginJSONFormatter` 的**纯逻辑层**测试
（坐标换算、选区裁剪、JSON 格式化/压缩/转义），UI 层不强行测。

### 5.2 按键路由抽成纯函数

`PalettePanel.sendEvent` 里的上下键/回车/Tab 路由逻辑照
`PaletteCoordinator.escapeAction` 的成功做法抽成纯函数，即可单测。
现有 `escapeAction` 是三档优先级，是最值得保留的测试范式。

### 5.3 遗留的 `Timer` / `DispatchQueue`

按 `AGENTS.md` 的并发规矩（定时优先 `Task` + `Task.sleep`，不要 `DispatchQueue`），
以下位置应在 Phase 5 评估迁移：

| 位置 | 现状 | 备注 |
|---|---|---|
| `PluginClipboard/Service/ClipboardMonitor.swift:20,35` | `Timer` 0.5s 轮询 | 高频定时，迁 `Task` + `sleep` 收益明显 |
| `PluginAI/UI/AIPortalView.swift:26` | `Timer.publish` 2s | SwiftUI 内，改 `.task` |
| `PluginTimestampConverter/UI/TimestampConverterView.swift:23` | `Timer.publish` 1s | 同上 |
| `QuickUI/Windows/Permissions/PermissionDrag.swift:237` | `Timer` 0.4s | 检查退出路径是否 `invalidate()` |
| `QuickPlatform/Input/MouseTriggerMonitor.swift:350` | `DispatchSource` timer | 长按阈值检测，C 回调邻域，谨慎 |
| `QuickPlatform/Shell/ShellCommandRunner.swift:90` | `DispatchQueue` | 有 `Sendable` 注释说明，谨慎 |

**注意**：这一项要逐个实测 CPU 占用再决定，不要为了「符合规矩」而改动已经稳定的
系统事件通路。`[需实测]`

---

## 执行顺序与依赖关系

```
Phase 0 (清死代码)
   ↓
Phase 1 (契约解耦)  ← 必须先行，Phase 2/4 都依赖它引入的能力协议
   ↓
   ├── Phase 2 (搜索管线)  ← 收益最大，风险最高
   ├── Phase 4 (设置页下沉) ← 可与 Phase 2 并行
   └── Phase 3 (依赖注入)
   ↓
Phase 5 (并发与测试补齐)
```

**每个 Phase 独立提交**，遵循 `AGENTS.md` 的提交规范（英文、Conventional Commits、
一个提交只做一件事）。Phase 之间不要混提，否则「哪次改坏了」无法追溯。

**每个 Phase 完成后的强制收尾**（照 `AGENTS.md`）：

```bash
./Scripts/run-tests.sh     # 必须全绿
./Scripts/build.sh         # 无新增警告（基线 0）
./Scripts/restart.sh       # 必须重启新实例，不能只 build
```

---

## 需要保持不动的设计（重构中严禁破坏）

这些是项目的正确决策，重构时容易「顺手改坏」：

1. **`AppCore` 是唯一所有者**，插件只在 `registerPlugins()` 里实例化
   （全仓唯一 `plugins.append(...)` 处）。
2. **不要给 `PaletteCoordinator` 加 `@Observable`** —— 会与 `AttributeGraph`
   形成重建死循环、CPU 打满。Phase 3 拆类型后同样适用。
3. **不要新增 actor。** 只有「主 actor」与「无隔离」两档。
4. **`Model/` 下不允许 `import AppKit` / `import SwiftUI`。**
5. **`project.yml` 是唯一真相**，改完必须 `xcodegen generate` 并一起提交。
6. **`CommandIndex` 的预处理设计**（建索引时做拼音与大小写折叠，按键只打分）
   —— 这是正确的性能设计，Phase 2 改造时不要退化成每次按键重新规范化。
7. **`PaletteCoordinator.escapeAction` 式纯函数** —— 把决策从副作用里拆出来的
   范式，Phase 5 应推广而不是替换。
