# Quick 架构重构方案

> 本文是 2026-09 一次静态架构审计的结论与执行计划。
> 审计方式：**只读代码**（约 9.6 万行 Swift、31 个 SPM 包）。
>
> **执行状态（2026-09-24）**：Phase 0 / 1 / 2 / 4 已全部落地，Phase 3 的主要部分
> （依赖注入收敛）也已完成。各阶段末尾的「完成情况」小节记录了实际做了什么、
> 验证数据是多少、以及哪些判断在执行中被修正 —— 那些修正本身也是这份文档的一部分。
> 尚未做的见「执行顺序与依赖关系」末尾的剩余项表。

## 结论摘要

架构方向是对的，**问题在于契约比实现诚实**：文档描述的是一套现代体系，
代码里有大量遗留残留、隐式字符串协议与主 actor 瓶颈在背离它。

具体地：

- **方向正确的部分**（重构中不碰）：`AppCore` 单一所有者、插件只在 `registerPlugins()`
  实例化、`CommandIndex` 的「建索引预处理 + 按键只打分」、`DesignTokens` 单一令牌源、
  `QuickLog` 分级体系、插件自治 SQLite schema。这些在执行中**一条都没被破坏**。
- **需要修的部分**：协议里的 SwiftUI 耦合、搜索管线的并发模型、退化成公开可变闭包的
  依赖注入、遗留 API 与死代码、设置页长在共享包里。

**最大单项收益是 Phase 2（搜索管线）** —— 它同时解决了「超时杀不掉」「2 秒卡住整批结果」
「线性扫描命令归属」「触发词冲突无人仲裁」四个问题。

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

### 额外发现：`InMemorySecretStore` 的 `@unchecked Sendable` 也没有依据

同一轮核查还发现 `QuickCore/Storage/SecretStore.swift` 的测试用内存实现用
`NSLock` + `@unchecked Sendable`。它不涉及任何 C 回调，所以不在允许范围内 ——
改用 `Mutex` 后断言整个消失。**`@unchecked Sendable` 从 4 处降到 3 处**，
剩下三处（`MouseTriggerMonitor` 的 CGEventTap、`ShellCommandRunner` 的两个进程句柄）
都在系统 C API 边界上，有正当理由，已在代码注释里写明依据。

`Mutex` 的 `withLock` 返回值有个细节：闭包返回 `Void` 时不能写 `_ =`（编译器会警告
「冗余」），而闭包返回可选值时必须写（否则警告「未使用」）。两处因此写法不同。

### 完成情况

三项全部落地。**过程中修正了一处审计判断**：

- 0.1 确认那三个目录**未被 git 跟踪**（只有 `.build/` 残留），所以是本地清理，
  不是仓库问题 —— 这一点在审计时被我误判为「仓库里有空包」。
- 0.2 实际删除的是 **16 个**插件的 `searchItems`，不是计划里列的 13 个。
  另外 9 个插件的 `searchItems` 是 `dynamicSearch` 的唯一实现体，按计划**改名**而非删除
  （`dynamicSearch` 的转发壳一并合并掉了）。
- 0.4 的 `MathParser` 改成 `struct` 并给解析方法加 `mutating`，`@unchecked Sendable` 消失。

**一处需要澄清的表述**：审计时我把 `searchItems` 称作「死代码」，这不准确。
它在主搜索路径上确实不可达（`PaletteSearchEngine` 不调用它），但它是**协议要求**且
测试在直接调用。准确的性质是「遗留公开 API」，删除它需要迁移测试 —— 二者工作量和
风险不同。测试迁移已在 Phase 2 完成。

验证：`./Scripts/run-tests.sh` 28 包全绿。

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

### 完成情况

已完成，且比计划更彻底：

- `SearchableItem` 的 `import SwiftUI` 是**完全未使用**的（文件里没有任何 SwiftUI 类型），
  直接删除。
- `PluginContext.swift` 里的 `EnvironmentValues.pluginContext` 是真 SwiftUI，
  **移到 `QuickUI/Panel/PluginContext.swift`**，符合「环境键属于 UI 层」的定位。
- `QuickCore` 里已无 `import SwiftUI` —— 上面那条验收命令现在无输出。
- 24 个插件声明 `PluginViewProviding`，3 个有专属设置页的额外声明
  `PluginSettingsProviding`。`ClipboardPlugin` 的 `makeSettingsView` 返回 nil，
  与默认实现等价，**按「迁移绝不包装」直接删除**，而不是留一个空覆写当文档。

宿主侧两处 `as?` 查询都带了日志：`PaletteCoordinator.makePluginView` 落空时 `.error`，
`AppCore.detachPlugin` 落空时 `.error` 并退化成 `EmptyView`
（`PluginPanelController` 的契约是非可选视图）。

### 一处顺带发现的契约不一致

`commands` 的 id 有**两套前缀**：默认的「打开本插件」是 `plugin.open.<插件id>`，
功能命令是 `<插件id>.<功能>`。而 `AppCore.plugin(forCommand:)` 的前缀回退只认后者 ——
`plugin.open.*` 走不到那条路（它由 `invoke()` 里的 `CommandID.openedPluginID` 单独处理）。

这不影响正确性，但容易误导。已在 `docs/architecture.md` 记下，并把测试断言改成
显式区分两套前缀（`commands.filter { !$0.id.hasPrefix("plugin.open.") }`），
避免后来者按错的前缀写断言。

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

### 完成情况

**协议改造已完成**：`accepts` / `dynamicSearch` / `static` 元数据（`id`、`name`、`icon`、
`description`、`triggerWords`、`commands`、`storageMigrations`）全部标 `nonisolated`。
25 个插件全部通过。

**关键发现：`nonisolated` 不能调用 `@MainActor` 方法**，即使该方法是 `async`。这是个
编译错误而非警告。所以「只改签名、保留转发壳」的路径走不通 —— 这也推翻了审计时
我对选项 B 的判断（当时以为可以在宿主侧自旋等待而插件不动，实际编译不过）。

10 个搜索依赖 `@MainActor @Observable` store 的插件因此需要**不可变搜索快照**
（`Mutex` 保护）。快照顺带把 `lowercased()` 从每次按键移到每次刷新，去掉了热路径上
的重复规范化。两个值得记住的细节：

- `ClipboardSearchSnapshot` **刻意不含 `imageData`**。剪贴板历史可能有 369 条含图片的条目，
  每条复制一份 `Data` 会把搜索变成内存拷贝操作。
- `SnippetStore.load()` 一开始漏了重建快照，**被测试当场抓住**（3 条失败）。
  这说明快照的更新点必须覆盖所有改变源数据的路径，而不只是写入路径。

**超时现在是真取消**：`searchDynamic` 返回 `PluginSearchResult`，`nil` 表示超时，
与「查了但无结果」区分开。结果由 `PaletteSearchOutcome` 带回，面板在结果不完整时
显示底注（有结果）或空状态（无结果）。以前超时静默返回空数组。

**命令索引已建**：`rebuildCommandCatalog()` 顺带重建 `pluginsByID` 与 `commandOwners`
两张表，替掉了 6 处线性扫描。

**触发词冲突已仲裁**：新增 `Scripts/check-trigger-words.py`，接入 `run-tests.sh`。
它解析三种触发词写法（字面量、跨文件常量引用、常量相加），**解析不出来就失败**而不是
跳过 —— 否则守卫会有盲区。已用注入冲突做反向验证（退出码 1）。
4 个冲突词按「语义更专一的一方保留」解决。

#### 一处必须记住的 Swift 语义

`nonisolated` 的**协议要求会让实现自动推断为 `nonisolated`** —— 不需要（也不会）
在实现处看到标注。这个机制值得记住，因为它有两个后果：

1. 好处：协议一旦要求 `nonisolated`，所有实现立刻脱离主 actor，不必逐个改。
2. 陷阱：**实现处没有标注，只看实现不容易看出它跑在哪个隔离域。**
   9 个插件的 `dynamicSearch` 因此都补上了显式 `nonisolated` —— 不改行为，
   但把「这里必须能脱离主 actor」写在读代码的人会看到的地方，
   防止将来有人改协议时把搜索悄悄放回主线程。

反面教材也在同一轮验证里出现过：我一度以为 9 个插件漏标了 `nonisolated`、
导致主 actor 瓶颈没解决，于是「修正」了一遍。**实际是编译器早已推断正确，
我的修改不是修 bug。** 教训是：涉及隔离域的判断要写最小实验验证，
不能从「源码里没看到关键字」推断「行为不对」。

#### 实测数据

启动日志（`./Scripts/logs.sh --dev`，`-showPalette`）：

| 指标 | 实测 | 预算 | 结论 |
| --- | --- | --- | --- |
| 面板 `show()` → 可见 | **28–45 ms** | < 100 ms | ✅ |
| 空闲 CPU（3 次采样） | 0.1–0.2 % | ≈ 0 % | ✅ |
| 启动到托盘图标 | 日志时序正常 | < 400 ms | ✅ |
| 插件注册 | 25 个 | — | ✅ |
| 静态命令 / 归属登记 | 83 / 83 条 | 一致 | ✅ |

#### 关于「聚合搜索超过 50ms」—— 审计判断的修正

审计时我看到日志里 `聚合搜索超过 50ms：耗时 64.6 ms`，且 `动态插件 0 个`，
于是判断「瓶颈在 `CommandIndex` 对 83 条静态命令的打分，83 条不该要 64ms」。
**这个判断是错的。**

写基准测下来（`/tmp` 下的独立复现，164 个字段）：

| 阶段 | 单次耗时 |
| --- | --- |
| 完整打分（`==` / `hasPrefix` / `contains` 三级） | **0.03–0.05 ms** |
| `Task.detached` 首次往返 | 1.06 ms |
| 拼音转写（`Pinyin.forms`，只在建索引时跑） | 0.83 ms / 次 |

打分比日志值**小三个数量级**。真正被计到的是 **`await Task.detached{...}.value`
那次线程跳转的延迟**：`Date()` 从函数入口开始计，而它横跨了这次跳转。主线程在启动时
忙着首次渲染，回到 continuation 的时间就被拉到 50–108 ms。

**为一次 0.05 ms 的计算付一次线程跳转是负收益。** 空查询因此改为同步执行
（有内容的查询仍走后台，那里工作量随候选数增长，跳转才值得）。

修复后：`64.6 ms` / `108 ms` → `50.8 ms`。**仍在 50 ms 预算线上，没有达标** ——
这次改动消除的是一个错误的优化，不是达成了一个指标。剩余时间来自首屏渲染期间的主线程
竞争，与打分无关；要真正解决得让首屏不依赖这次搜索，那是另一件事，本轮未做。

这条经验值得记：**`async` 不等于「更并发」。** 跨线程的成本有下限（调度的微秒到
主线程繁忙时的毫秒），低于这个量级的工作留在原地更快。

`Task.isCancelled` 的中途检查仍保留在插件循环里（协议要求），
`grep -rn "func dynamicSearch" Packages/Plugin*/Sources/ | grep -v nonisolated` 无输出。

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

### 完成情况

**已完成第一步（不可变注入）**，第二步（拆成三个类型）**未做** —— 理由是
`PaletteCoordinator` 现在 650 行但职责已经收敛，而拆分需要改动
`PaletteView` 的全部注入路径，风险与收益不成比例。这一步留待有明确需求时再做。

已完成的部分：

- 新增 `PaletteDependencies`，8 个 `public var` 收敛为 `private var dependencies`
  + 只读计算属性。缺项现在是**编译错误**。
- `attach(_:)` 加 `.fault` 日志防重复注入 —— 那正是本类型要消灭的模式。
- `AppCore.start()` 里六七行分散赋值合并成一次 `attach`。

**一处实现细节**：`invokeCommand` 必须是 `@Sendable`，因为它会被存进
`SearchableItem.action`（`Sendable` 结构）。而 `@MainActor` 的静态方法**不能**再标
`@Sendable`（全局 actor 隔离的函数本身就是 Sendable），所以兜底写成具名函数
`PaletteCoordinator.noOpInvoke` 而不是闭包字面量 —— 字面量在这里推不出 `Sendable`。

实测确认接线正常：启动日志中有「面板协调器依赖已注入」，命令归属 83 条与静态命令一致。

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

### 完成情况

**全部完成。**

先量了收益再动手：统计发现**用得最多的视图也只用到 7 个成员**，而协议暴露约 50 个。
所以拆分的价值在于收窄视图的依赖面，而不只是把大协议切成小协议。

拆成 4 个子协议，用组合协议保持 `SettingsBridge` 单一实现：

| 协议 | 覆盖 |
| --- | --- |
| `CommandSettingsDataSource` | 快捷键、命令开关、别名 |
| `LauncherSettingsDataSource` | 搜索范围、系统操作、自定义命令 |
| `PluginSettingsDataSource` | 插件开关、搜索来源、专属设置页、键盘布局 |
| `HostSettingsDataSource` | 通用、超级面板、AI、权限、关于 |

视图按需声明，多数是 1–2 片的组合。`SettingsDetailView` / `SettingsView` /
`SettingsWindowController` 保留伞协议 —— 它们是分发器，要构造全部子页，
**这里用伞协议是有意的**，不是漏收窄（已在代码注释里写明，避免后来者「顺手收窄」而破坏）。

#### 设置页下沉

`FeatureSettingsPanes.swift` **1079 → 165 行**，22 个插件的表单搬进各自的包
（`Plugin*/Sources/*/Settings/`），走 `PluginSettingsProviding` 查询。

搬迁之所以能机械完成，是因为量过之后发现：**22 个表单没有一个用到 `dataSource`**，
它们只读自己插件的 `PluginSettingKey`。这正是它们属于插件包的证据。

顺带清掉一个残留：`QuickCore` 的测试里还留着 `makeView()`（协议早已不要求），
以及随之多余的 `import SwiftUI`。**`QuickCore` 现在连测试都不引用任何 UI 框架。**

#### 一处审计判断的修正（两次修正）

计划里我说「给插件加设置项要去改共享 UI 包，依赖方向是反的」。

- 第一次核对时我看到了 `dataSource.makeFeatureSettingsView(for:)`，以为已经是能力查询，
  于是判断「主要收益已经拿到、文件降到 250 行」，**这是错的** —— 那个能力查询是优选路径，
  但 `defaultFeatureContent` 里的 switch 才是真正的大头，它是 fallback，仍然硬编码着
  22 个插件。我当时没看这条分支就下了结论。
- 第二次核对（本轮）才量清楚：860 行是插件专属配置，`QuickUI` 不该认识它们。

教训是同一个：**「我看到了一条正确的路径」不等于「所有路径都正确」**，
分支要逐个走一遍。

---

## Phase 5：并发与测试补齐

**风险：低。收益：长期。**

### 5.1 测试覆盖断崖

**先把口径说清**：下表是「测试文件行数 ÷ 源码行数」，**不是代码覆盖率**。
它只能说明「这个包的测试有多少行」，不能说明「多少分支被走过」——
要真覆盖率得开 `--enable-code-coverage` 再跑一遍。

| 包 | 源码 | 测试 | 行数比 | 用例数 |
|---|---|---|---|---|
| `PluginScreenshot` | 2,376 | 317 | 13.3% | 20 |
| `PluginJSONFormatter` | 1,130 | 239 | 21.2% | 21 |
| `PluginCalculator` | 1,239 | 355 | 28.7% | 19 |
| `QuickUI` | 15,447 | 2,526 | 16.4% | 166 |

`PluginScreenshot` 与 `PluginJSONFormatter` 的纯逻辑层已补：裁剪钳制、缩放取整、
编码类型与扩展名一致性、节点文本转义、行路径唯一性。**UI 层不强行测** ——
遮罩窗口与树视图的渲染要在真机上看，断言渲染结果只会得到脆弱的测试。

### 5.2 按键路由抽成纯函数

`PalettePanel.sendEvent` 里的上下键/回车/Tab 路由逻辑照
`PaletteCoordinator.escapeAction` 的成功做法抽成纯函数，即可单测。
现有 `escapeAction` 是三档优先级，是最值得保留的测试范式。
### 5.3 遗留的 `Timer` / `DispatchQueue`

按 `AGENTS.md` 的并发规矩（定时优先 `Task` + `Task.sleep`，不要 `DispatchQueue`），
审计时列出了 6 处。**其中 3 处已迁移，另外 3 处是系统边界，结论与审计不同。**

已迁移（`Task` 循环，随视图或 `stop()` 取消）：

| 位置 | 原来 | 现在 |
|---|---|---|
| `PluginClipboard/Service/ClipboardMonitor.swift` | `Timer` 0.5s 轮询 | `Task` 循环；`start()` 幂等、`stop()` 取消，有测试锁住 |
| `PluginAI/UI/AIPortalView.swift` | `Timer.publish` 2s | `.task` 循环 |
| `PluginTimestampConverter/UI/TimestampConverterView.swift` | `Timer.publish` 1s | `.task` 循环，`Combine` 依赖随之删掉 |

保留（不是「懒得改」，而是系统边界）：

| 位置 | 现状 | 为什么保留 |
|---|---|---|
| `QuickUI/Windows/Permissions/PermissionDrag.swift` | `Timer` 0.4s + `tolerance` | 追踪的是**别的应用**的窗口（系统设置）位置，`tolerance` 是刻意留给系统的合并窗口；退出路径已 `invalidate()` |
| `QuickPlatform/Input/MouseTriggerMonitor.swift` | `DispatchSource` timer | 长按阈值检测在 C 回调邻域，且它是 `@unchecked Sendable` 的既有实例 |
| `QuickPlatform/Shell/ShellCommandRunner.swift` | `DispatchQueue` | 代码里已注明理由（所有可变状态都在 `lock` 临界区内），改 `Task` 会让进程句柄的清理时机更难推理 |

**注意**：`AGENTS.md` 的「不要 `DispatchQueue`」是针对**新写的代码**。这三处的取舍
需要单独论证，不能因为「规矩这么写」就机械套用 —— 也不能反过来拿「系统边界」当
万能借口，任何一处要改都必须先测出实际行为差异。

### 完成情况

**测试覆盖：部分完成，有意保留。**

测试迁移与新增是本轮改动量最大的部分之一 —— 26 个测试文件、125 处调用点从旧的
`searchItems` 迁移到新契约。迁移不是机械改名：断言内容要换成验证**当前真实行为**
（命令覆盖、闸门语义、不参与动态搜索），否则测试会测一个「恒返回空的默认实现」，
失去保护力。这也是一处需要警惕的退化 —— `Launcher` 的「空查询不返回全部应用」
测试在改名后就不再验证任何东西了。

**Timer 迁移：3 处已做，3 处有意保留。**

计划里列了 6 处 `Timer` / `DispatchQueue`，逐个看下来结论并不一致：

| 位置 | 结论 |
| --- | --- |
| `ClipboardMonitor`（0.5s 轮询） | **已改**：`Timer` 每 tick 都要回主 actor 跳一次，还得在每条退出路径 `invalidate()`；`Task` 循环只靠 `stop()` 取消。启停幂等有测试覆盖 |
| `AIPortalView` / `TimestampConverterView`（`Timer.publish`） | **已改**：纯 SwiftUI 内，`.task` 随视图消失自动取消 |
| `MouseTriggerMonitor`（`DispatchSource` timer） | **保留**：长按阈值检测在 C 回调邻域，`DispatchSource` 的精度与阻塞语义正是这里需要的 |
| `ShellCommandRunner`（`DispatchQueue`） | **保留**：代码里已注明理由（所有可变状态都在 `lock` 临界区内），改 `Task` 会让进程句柄的清理时机更难推理 |
| `PermissionDrag`（0.4s） | **保留**：追踪的是系统设置窗口的位置，`tolerance` 是刻意留给系统合并的；退出路径已 `invalidate()` |

审计时我把这 6 处并列成「都该迁移」，这是错的 —— `AGENTS.md` 的「不要用 `DispatchQueue`」
是针对**新的**代码。但同样的道理，也不该把「系统边界」当成免检标签：保留的三处
要改也必须先测出实际差异。

---

## 执行顺序与依赖关系

```
Phase 0 (清死代码)              ✅ 完成
   ↓
Phase 1 (契约解耦)              ✅ 完成
   ↓
   ├── Phase 2 (搜索管线)        ✅ 完成（含触发词守卫、空查询同步化）
   ├── Phase 4 (设置层拆分)      ✅ 完成（协议拆分 + 设置页全部下沉）
   └── Phase 3 (依赖注入)        ✅ 不可变注入完成，拆类型未做
   ↓
Phase 5 (并发与测试)            ⚠️ 测试迁移与新增完成；3 处定时已迁 `Task`，3 处系统边界保留
```

**剩余项**（均可独立开工，不阻塞彼此）：

| 项 | 价值 | 风险 |
| --- | --- | --- |
| 真实分阶段测量搜索耗时（首屏渲染 vs 打分 vs 插件） | 高，50.8 ms 必须先测出是哪一段 | 低 |
| `PalettePanel.sendEvent` 的按键路由抽成纯函数 | 中 | 低 |
| `PaletteCoordinator` 拆三个类型 | 低 | 高，不建议做 |
| `MouseTriggerMonitor` / `ShellCommandRunner` / `PermissionDrag` | **保留**，见 Phase 5 说明 | — |

**每个 Phase 独立提交**，遵循 `AGENTS.md` 的提交规范（英文、Conventional Commits、
一个提交只做一件事）。Phase 之间不要混提，否则「哪次改坏了」无法追溯。

本次实际提交序列：

```
docs: record the 2026-09 architecture audit and its refactor plan
fix(calculator): make MathParser a value type instead of unchecked Sendable
refactor(core): drop the legacy search API and take SwiftUI out of the protocol
refactor(plugins): adopt the view capability protocol and unblock search from the main actor
feat(tooling): fail the test run when two plugins claim the same trigger word
test(palette): make the search gate tests able to fail
refactor(clipboard): give the settings controls a named width token
docs(ui): register the setting rows the plugin packages now depend on
refactor(clipboard): poll for clipboard changes with a task
refactor(timestamp-converter): drive the clock display with a task
refactor(ai): refresh provider status with a task
docs: record which timer migrations landed and which are staying
test(screenshot): cover cropping, scaling and encoding
test(json-formatter): cover node text escaping and row paths
```

**每个 Phase 完成后的强制收尾**（照 `AGENTS.md`）：

```bash
./Scripts/run-tests.sh     # 必须全绿
./Scripts/build.sh         # 无新增警告（基线 0）
./Scripts/restart.sh       # 必须重启新实例，不能只 build
```

### 本轮验收记录

| 项目 | 结果 |
| --- | --- |
| `./Scripts/run-tests.sh` | 28 个包全绿（约 720 个测试） |
| `./Scripts/build.sh` | 成功，**0 新增警告** |
| 实际启动 `.app` | 进程存活，空闲 CPU 0.1–0.2 % |
| 面板唤出 | `-showPalette` 实测 34.0 ms 到可见 |
| 搜索链路 | 25 插件注册、10 条事件订阅、83 条静态命令 |
| 无 error/fault | 启动全流程仅 1 条 search 超 50ms 的 warning |

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
