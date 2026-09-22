# 架构

本文件回答「东西挂在哪、谁拥有谁、什么时候被创建」。写代码风格看
[standards.md](standards.md)。

---

## 1. 分层与依赖方向

```
┌──────────────────────────────────────────────────────────┐
│  Quick（应用目标）                                        │
│  QuickApp / AppDelegate / AppCore / StatusItemController  │
│  —— 唯一的 composition root，唯一 import Plugin* 的地方    │
└───────────────────────┬──────────────────────────────────┘
                        │
        ┌───────────────┼───────────────┐
        ▼               ▼               ▼
  ┌──────────┐   ┌───────────┐   ┌──────────────┐
  │ Plugin*  │   │  QuickUI  │   │ QuickPlatform│   （27 个 / 1 个 / 1 个）
  └────┬─────┘   └─────┬─────┘   └──────┬───────┘
       │               │                │
       └───────────────┴────────────────┘
                       ▼
                 ┌───────────┐
                 │ QuickCore │
                 └───────────┘
```

**规则：箭头只能向下。** 具体到 import：

- `QuickCore` 不 import 任何本项目其他包，也不 import AppKit / SwiftUI（它只依赖 Foundation
  和 `SwiftUI` 的 `AnyView` 类型 —— `QuickPlugin.makeView()` 签名需要）。
- `QuickUI` / `QuickPlatform` 依赖 `QuickCore`，**不**依赖任何插件。
- `Plugin*` 依赖 `QuickCore` + `QuickUI`，需要系统能力时再加 `QuickPlatform`。
  **插件之间永不互相依赖。**
- `Quick/` 依赖全部。只有它能 import 各插件。

**为什么插件间不能互相依赖：** 27 个插件两两依赖会变成一张网，任何改动都会波及全仓，
且没法单独测试。需要协作时走 `EventBus`。

---

## 2. `AppCore`：唯一的所有者

[`Quick/AppCore.swift`](../Quick/AppCore.swift) 是 `@MainActor final class`，
`static let shared`。整个应用只有它在持有长生命周期对象。

### 它拥有什么

| 属性 | 类型 | 职责 |
| --- | --- | --- |
| `hotKeyService` | `HotKeyService` | Carbon 全局快捷键注册与回调 |
| `paletteCoordinator` | `PaletteCoordinator` | 面板生命周期、定位、聚合搜索 |
| `permissionService` | `PermissionService` | 辅助功能 / 屏幕录制权限 |
| `pasteboardService` | `PasteboardService` | 剪贴板读写 |
| `settingsStore` | `SettingsStore` | 插件开关之类的偏好 |
| `keyboardLayoutService` | `KeyboardLayoutService` | 系统输入源枚举与切换（面板打开时强制到指定布局） |
| `appIndex` | `AppIndex` | 应用清单与模糊搜索 |
| `hud` | `HUDController` | 底部轻量提示 |
| `pluginPanelController` | `PluginPanelController` | 分离窗口管理（创建、单例、尺寸记忆） |
| `launchAtLogin` | `LaunchAtLogin` | 登录项（`SMAppService`） |
| `statusItemController` | `StatusItemController` | 菜单栏图标与菜单 |
| `plugins` | `[any QuickPlugin]` | 全部 27 个插件实例 |
| `subscriptions` | `[EventSubscription]` | 事件订阅句柄（不持有就会被释放） |

### `start()` 的固定顺序

顺序是有意的，改动前想清楚依赖：

1. `registerPlugins()` —— 组装插件（**唯一实例化插件的地方**）
2. `paletteCoordinator.setPlugins(plugins)` —— 让面板能搜索
3. `wireEventBus()` —— 订阅事件，把事件接到协调器/剪贴板/HUD
4. 热键：设 `onCommand` 回调 → `hotKeyService.start()` → 按命令目录同步注册
5. `statusItemController.install()` —— 菜单栏图标
6. `observeDebugWakeSignals()` —— 调试用分布式通知
7. `Task { await appIndex.refresh() }` —— **异步**扫描应用，不阻塞启动
8. 对每个已启用插件调用 `activate()`
9. 若启动参数带 `-showPalette`，立即显示面板

退出走 `prepareForTermination()`：停热键 → 摘菜单栏 → `deactivate()` 各插件 →
`EventBus.shared.removeAll()`。

### 新增状态的规矩

- 新的长生命周期状态**挂到 `AppCore` 上**，在 `start()` 里接线。
- **绝不**另起一个 `static let shared` 单例来放状态。目前只有两个有意的单例：
  `AppCore.shared` 和 `EventBus.shared`，不要加第三个。跨窗口的控件（例如
  `IconCache`、`ShortcutRecorderCoordinator`）也是单例，但它们是无状态的工具，
  不是状态的所有者 —— 新增长生命周期状态时不要照着它们抄。
- 视图**不要**直接拿 `AppCore`。视图通过 `@Environment` 拿协调器，或通过构造参数注入
  依赖（例如 `LauncherPlugin(appIndex:)`）。

---

## 3. 插件契约：`QuickPlugin`

[`Packages/QuickCore/Sources/QuickCore/Protocols/QuickPlugin.swift`](../Packages/QuickCore/Sources/QuickCore/Protocols/QuickPlugin.swift)

```swift
@MainActor
public protocol QuickPlugin: AnyObject, Sendable {
    static var id: String { get }
    static var name: String { get }
    static var icon: String { get }
    static var commands: [CommandDescriptor] { get } // 默认为「打开本插件」
    var isEnabled: Bool { get set }
    func searchItems(query: String) async -> [SearchableItem]
    func accepts(query: String) -> Bool          // 动态搜索闸门，默认 false
    func dynamicSearch(query: String) async -> [SearchableItem]
    func perform(commandID: String)              // 热键和搜索共用
    func makeView() -> AnyView
    func makeSettingsView() -> AnyView?
    func activate()
    func deactivate()
}
```

协议提供了默认实现：`commands` 默认一条打开插件的命令、`accepts` 默认 false、
`dynamicSearch` 默认空、`perform` 默认导航进插件面板、`isEnabled` 默认 `true`、
`makeSettingsView` 默认 `nil`、`searchItems` 默认空、`activate`/`deactivate` 默认无操作、
`defaultItems` 默认取「触发词裸查询的第一条」。**只实现你需要的那些**，
不要写空实现占位。

主面板搜索不再对每个插件调用 `searchItems`。静态命令进内存索引，在后台线程打分；
只有 `accepts` 返回 true 的插件才会跑 `dynamicSearch`。空查询每个插件至多一条
`showsWhenQueryEmpty` 的命令，再加上最近使用。命令 id 和插件 id 一样，发布后不能改。

快捷键只有一张表，键是 `hotkey.command.<命令 id>`。一条组合键只对应一个命令。
命令关掉后绑定还在，但 Carbon 不注册，搜索索引里也没有它。设置侧边栏上面是
通用、外观、快捷键、权限、搜索，「插件」是一级分类，每个插件是它下面的一项，最后是关于。
快捷键页的系统区只展示面板固定键，只有唤出面板可以改；下面是用户自己添加的绑定。
绑定的右边是关键字，不是命令下拉框。一条命令可以挂多个关键字，不同关键字可以打开
同一个插件里的不同功能。主面板输入「锁屏」唤醒锁定屏幕，输入「全屏」只打开全屏截图。
对不上或同时对上多条时不猜测。
插件不调用 `RegisterEventHotKey`，系统能力（热键、权限、剪贴板、应用索引）只走 QuickPlatform。
主面板的尺寸拖过四边之后记在 `quick.palette.width` / `quick.palette.height`，换缩放档时丢掉。
主面板与分离窗口用**同一套缩放机制**：窗口带 `.resizable`，AppKit 在四边提供系统缩放热区与
光标；尺寸的上下限在 `PalettePanel.windowWillResize` 里按当前屏幕夹，缩放结束
（`windowDidEndLiveResize`）才写回偏好。不要退回「自绘一圈透明 `NSView` 模拟缩放」——
那既拿不到系统光标，也和分离窗口手感不一致。

### 不变量

- **`static var id` 一旦发布就不能改。** 它是 `SettingsKey.pluginEnabled(id)` 的键，
  改了等于用户设置丢失。
- **`searchItems` 必须是纯查询。** 不要在里面激活插件、写盘、发网络请求、改 `isEnabled`。
  它可能在每次按键时被调用（虽然并发，但不是免费的）。要缓存就在 `activate()` 里预热。
- **`defaultItems()` 在首屏每条最多出一次，而且必须走 `searchItems`。** 空查询时
  `searchItems(query: "")` 会被插件自己的触发词闸门挡掉、返回空数组，所以首屏不能靠它 ——
  这就是 `defaultItems()` 存在的原因。默认实现「用触发词当查询词、取第一条」，
  于是每个插件都自动有一个入口，而不会把首屏铺成插件自己的列表页。走同一条搜索路径的
  意义在于：首屏那条和搜到的那条是同一份代码产出的，标题、图标、动作永远一致。
  `LauncherPlugin` 覆盖它返回空 —— 它贡献的应用列表本身就是首屏主体。
- **`searchItems` 必须尊重防抖与取消。** 调用方（`PaletteCoordinator`）只在防抖后调用，
  但插件内部若有昂贵准备，要检查 `Task.isCancelled`。
- **`makeView()` 返回的视图不要持有 `AppCore`。** 需要能力就通过插件构造器注入。
- **`activate()` / `deactivate()` 必须成对且幂等。** 插件可能被反复启停。
- **`deactivate()` 里要落盘。** 未保存的运行时状态在退出时就丢了。

### 注册流程

插件**不自注册**。加一个插件要做四件事：

1. 写 `<Name>Plugin.swift` 实现协议。
2. 在 `AppCore.registerPlugins()` 里 `plugins.append(...)`。
3. 在 `project.yml` 的 `packages:` 加路径、在 `Quick` target 的 `dependencies:` 加
   `- package: Plugin<Name>`，然后 `xcodegen generate`。
4. 在 `docs/features/<id>.md` 写下这个插件的不变量。

第 2 步是唯一实例化点。如果你发现自己在别处 `new` 一个插件，那就是错了。

### Quick 只支持内置插件

"插件"在这里指的是**编译期插件**，不是可以装第三方代码的扩展系统：

- 所有插件与宿主一起编译、一起签名。`project.yml` 的依赖列表就是全部插件清单，
  没有扫描目录、没有动态加载、没有安装入口 —— 设置页里也这么写。
- 因此插件的边界靠**契约**保证（`QuickPlugin` 协议 + 单向依赖 + 编译期检查），
  而不是靠运行时沙箱。插件的代码权限和宿主一样，写插件时按这个前提思考。
- 想做第三方生态，就需要动态加载、版本化的宿主 API、签名与沙箱策略，
  以及去改这份文档里的自注册禁令 —— 那是一次架构变更，不要顺手做。

一个插件应该大到什么程度才值得单独存在？`parse`/`format` 这类纯逻辑抽到 `Model/` 里
能独立测，就够一格了 —— 11 个开发者工具就是这么从 `devtools` 容器里拆出来的。

---

## 4. `EventBus`：插件间唯一的通信方式

[`Packages/QuickCore/Sources/QuickCore/Events/EventBus.swift`](../Packages/QuickCore/Sources/QuickCore/Events/EventBus.swift)

```swift
@MainActor public final class EventBus: Sendable {
    public static let shared: EventBus
    public func post<E: PluginEvent>(_ event: E)
    @discardableResult
    public func on<E: PluginEvent>(_ type: E.Type, handler: @escaping (E) -> Void) -> EventSubscription
    public func unsubscribe(_ subscription: EventSubscription)
    public func removeAll()
}
```

事件是 `Sendable` 的值类型，自带 `static var name` 作为路由键。内置事件：

| 事件 | 用途 |
| --- | --- |
| `NavigateEvent` | 让面板跳到某个插件（可带 query 上下文） |
| `ShowPaletteEvent` / `HidePaletteEvent` | 显隐面板 |
| `CopyToClipboardEvent` | 请求写剪贴板 |
| `ShowHUDEvent`（+ `HUDTone`） | 请求弹一条提示 |
| `DetachPanelEvent` | 请求将当前插件分离为独立窗口 |
| `ClipboardChangedEvent` | 剪贴板内容变了（剪贴板插件发，宿主订阅）—— 只带时间点，不带内容 |

### 不变量

- **必须保存 `EventSubscription`。** 它是句柄，返回值丢弃就等于随 ARC 一起取消订阅。
  保存到 `AppCore.subscriptions` 或插件自己的属性里，并在 `deactivate()` 时释放。
- **事件处理器在主 actor 上同步执行。** 不要在里面做重活；需要异步就 `Task { }`。
- **事件名（`static var name`）是全局命名空间**，用 `quick.<区域>.<动作>` 格式，
  不要和别的插件撞。
- **不要用 `EventBus` 做请求-响应。** 它没有返回值。需要拿结果就直接调那个插件 ——
  但那种情况说明这两个插件的边界画错了，先重新想。

---

## 5. 数据模型

### `SearchableItem`

[`Packages/QuickCore/Sources/QuickCore/Models/SearchableItem.swift`](../Packages/QuickCore/Sources/QuickCore/Models/SearchableItem.swift)

```swift
public struct SearchableItem: Identifiable, Sendable {
    public let id: String
    public let pluginID: String
    public let title: String
    public let subtitle: String?
    public let icon: String
    public let iconType: IconType      // .symbol / .appIcon(path) / .image(name)
    public let relevance: Double       // 0...1，聚合后按它降序排
    public let shortcutHint: String?
    public let action: @MainActor () -> Void
}
```

- `Hashable` **只基于 `id`**。所以 `id` 必须在插件内唯一且稳定；重复 id 会让列表错乱。
- `relevance` 是跨插件比较的**唯一**依据。`MatchQuery.score(_:)` 给出的阶梯是：
  完全匹配 `1.0`、前缀匹配 `0.9`、包含匹配 `0.7`、子序列 `0.35…0.65`、不匹配 `0`。
  汉字还能按拼音命中（全拼与首字母两种形态），但拼音的分整体压在字面之下 ——
  用户打 `wx` 时，名字真叫 `WX` 的东西排在「微信」前面（见 `QuickCore/Search/`）。
  插件可以在这个基础上叠加自己的权重（`LauncherPlugin` 就是
  `匹配分 * 0.7 + 使用频率 * 0.3`），但**不要所有结果都给 `1.0`** ——
  那等于放弃了排序，列表顺序会变成随机。
- `withRelevance(_:)` 复制一份、换掉相关度，用于「同一条目在不同场景下权重不同」。
  它只改这一个字段，`id` / 图标 / 动作原样带过去 —— 换权重不该换掉条目本身。
- **空查询（首屏）的顺序由协调器最后再排一次。** 聚合、去重、按相关度排序之后，
  协调器把「最近使用过的」条目提到最前（`PaletteCoordinator.promotingRecents`，
  取最近 12 条），其余保持原顺序。首屏回答的是「我刚用过什么」，不是「谁的分数高」；
  **非空查询完全不参与这次重排** —— 那时相关度才是用户要的，按时间插队只会打乱搜索结果。
- `action` 在按下回车/点击时于主 actor 执行。它应该**只发事件或调用已注入的依赖**，
  不要直接 `NSWorkspace` 之类的全局调用（除了启动应用这种确实没有别的写法的情况）。

### 持久化

**偏好进 `UserDefaults`，插件数据进一个 SQLite 库。** 这条分界是这个仓库里最容易被搞错的一件事，
所以写清楚理由：

| | 放哪 | 为什么 |
| --- | --- | --- |
| 用户偏好（开关、快捷键、缩进风格、窗口尺寸） | `UserDefaults` | 量小、用户可改、要能一键重置。`@AppStorage` 是 SwiftUI 里绑定控件的正统写法，换成自定义存储只会多一层包装。 |
| 插件数据（剪贴板历史、笔记、片段、使用频率） | `quick.db`（SQLite） | 是**用户内容**：不可重置、会增长、要和别的数据一起备份。整份读进内存再整体重写的老做法撑不住，也查不动。 |

两者混在一起会怎样：`UserDefaults` 里放了几千条剪贴板历史之后，「重置设置」就变成了
「删掉用户的历史」。反过来，把「上次选的编码模式」塞进数据库，也只是给一件小事配一套 schema。

**路径**：所有落盘位置走
[`AppPaths`](../Packages/QuickPlatform/Sources/QuickPlatform/System/AppPaths.swift)
（`applicationSupport()` / `database()` / `logs()` / `pluginData(_:)`）。
**不要自己拼 `~/Library/...`**。`AppPaths` 已按 `Bundle.main.bundleIdentifier` 分目录，
Debug（`.dev`）与 Release 互不污染。

### 存储：一个库，两层能力

[`SQLiteDatabase`](../Packages/QuickCore/Sources/QuickCore/Storage/SQLiteDatabase.swift) 是
系统 `libsqlite3` 上的一层薄封装（**零第三方依赖**：`import SQLite3` 是 SDK 自带的系统模块）。
[`PluginStorage`](../Packages/QuickCore/Sources/QuickCore/Storage/PluginStorage.swift)
是交给插件的句柄，它绑定插件 id，插件写不到别人的命名空间里去。

1. **键值层（默认选择）**：`storage.set(_:forKey:)` / `value(_:forKey:)`，值是任意 `Codable`。
   存「上次选的是哪个模式」这类零散状态用它 —— 不必为一件小事设计文件格式。
   这是 Fasty `plugin_data` 表的做法。
2. **插件自己的表**：需要排序、分页、过滤的批量数据（剪贴板历史、笔记、片段）用
   `storage.database` 直接写 SQL，schema 通过 `QuickPlugin.storageMigrations` 声明。

**表结构归插件所有**：宿主只跑一遍声明，不预先建任何插件表，也不读插件表。
宿主自己也有两份 schema，在 `AppCore.migrateHostStorage()` 里跑：`core.plugin_data`
（插件的零散键值）与 `core.usage_history`（最近使用过的 `SearchableItem.id`）。

「最近使用」放在宿主层而不是某个插件里，是因为它是**跨插件**的事实：用户可能刚用过一个
开发工具、再打开一个应用、又用了翻译。每个插件各记各的，宿主就回答不了「按最近使用排序」
—— 而首屏要的正是这个顺序。它与启动器插件的 `RankingStore` 分工不同：`RankingStore`
记**使用次数**（与时间无关，用于给搜索结果加权），`UsageHistory` 记**最后一次是什么时候**
（昨天启动过 20 次的东西，不该排在刚刚用过的翻译前面）。

#### 迁移按 id 记账，不用递增版本号

迁移是一个 `(id, [SQL])`。id 形如 `clipboard.history`、`notes.items`，写在
`schema_migrations` 表里作为「这段 DDL 跑过没有」的判据，**一旦发布就不能改**。

用字符串 id 而不是版本号，是因为 schema 由多方声明（宿主一份 + 每个插件一份）：递增编号会
强迫所有插件去协调「谁拿 7 谁拿 8」，加一个插件就要动别人的编号。id 各自独立，加插件不需要碰任何人。
每个迁移在自己的事务里执行，失败就停在上一个完整状态，不会留一个改了一半的表结构。

#### 为什么是同步 API，而不是 actor

`SQLiteDatabase` 的所有方法都是同步的，内部用一个 `Synchronization.Mutex` 保护句柄
（所以它是编译器保证的 `Sendable`，不是 `@unchecked`）。理由：

- 调用点全在同步路径上 —— 插件的 `activate()` 是同步的，视图直接在 body 里读 store 的数组。
  做成 actor 的话 `await` 会顺着调用链传染到插件生命周期和所有视图，而并发收益是零。
- 本地 SQLite 的一次写入是微秒级，而且写操作本来就要串行。串行化在几千条数据的规模下代价可以忽略。

连接参数与 Fasty 一致：`journal_mode=WAL`（读写不互相阻塞）、`busy_timeout=5000`、
`synchronous=NORMAL`（WAL 下仍然安全）、`foreign_keys=ON`。

#### 写操作的两条硬规则

1. **数据库是唯一真相。** 内存里的数组只是给 SwiftUI 读的缓存。任何在 SQL 里做过剪枝/删除的
   操作，结束后必须从库里重读缓存（见 `ClipboardStore.reloadCacheFromDatabase`）——
   自己在内存里推算「应该剩哪些」迟早会和库里的不一致。
2. **一次业务动作要么一个事务，要么一个语句。** 例如剪贴板「去重 + 插入 + 剪枝」必须同时发生，
   顺序也有讲究：先删重复再插入，反过来会把刚插入的这条自己删掉，而且不报错。

`try?` 一律不可接受：写失败被静默吞掉，表现出来就是「数据自己没了」。

#### 偏好键走注册表

插件选项的键集中在
[`PluginSettingKey`](../Packages/QuickCore/Sources/QuickCore/Models/PluginSettingKey.swift)。
以前键名只以字面量形式散落在设置页和存储层两处，拼错一个字母就是「设置改了没反应」，
编译器还帮不上忙。现在两边引用同一个常量。

---

## 6. 面板与窗口

`PaletteCoordinator` 拥有面板，负责显隐、定位、模式切换，**不含任何业务逻辑**。

### 面板打开时的自动行为

`show()` 在把面板推上前台之前先跑 `applyAutoBehavior()`，处理两件与「用户上次在干什么」
有关的事。判定与取数据分开：`PaletteAutoBehavior` 里是纯函数（只比较时间点），
协调器只负责取剪贴板、落结果 —— 于是时间窗的边界（`<` 还是 `<=`）可以直接测。

- **刚复制过东西就填进搜索框**（时间窗 5 / 10 / 30 秒）。复制完立刻唤出面板，
  多半就是要拿这段内容去搜或去粘。
- **上次的查询放太久就清掉**（空闲时间 1 / 3 / 10 分钟），否则每次打开都看到残留的关键词。

两个设置都经 `PaletteAutoBehavior.pasteWindow(from:)` / `clearIdle(from:)` 读，
**出厂默认值定义在那里**，设置页的 `@AppStorage` 引用同一个常量。这不是洁癖：
`@AppStorage` 的默认值只在键不存在时生效，而 `integer(forKey:)` 在键不存在时读到 0
（＝关闭），两边各写各的就会出现「设置页写着 5 秒内、实际行为是关闭」。规则见
[ui.md §11](ui.md#11-设置页的控件必须真的生效)。

搜索框文本由 `PaletteQuery` 持有（不持有窗口的 `@Observable`），**协调器与视图共用同一份**。
它存在的理由是协调器需要在面板外面改写输入框（自动粘贴、自动清空、`show(query:)` 预填），
而视图的 `@State` 只在首次出现时读一次初值 —— 面板复用同一个 `NSHostingView`，
所以「打开时传入的查询」曾经完全到不了输入框。

剪贴板最后一次变化的时刻只有剪贴板插件知道（它在轮询 `NSPasteboard.changeCount`），
所以它发 `ClipboardChangedEvent`，协调器订阅下来只记一个时间点 —— 事件不带内容，
免得把可能很大的文本在事件里传一遍。

### 外观

`AppCore.applyAppearance()` **是唯一给 `NSApp.appearance` 赋值的地方**。`AppAppearance`
（跟随系统 / 浅色 / 深色）存在 `SettingsKey.appearance` 里，`.system` 映射成 `nil`，
把选择权交回 AppKit —— 系统换外观时它自己跟进，我们不必轮询，也不必为「跟随系统」
单写一条路径。

只赋这一处，是因为它是应用级的：面板、设置窗口、分离窗口、HUD 一起跟着变，逐个窗口设置
迟早会漏掉一个。`DesignTokens` 里的颜色又都是 `NSColor(name:) { appearance in … }` 这类
动态颜色，**在绘制时**才按当前外观解析，所以改完不需要重建任何视图。

图标缓存是唯一的例外：位图是按外观出图的，翻了面要让它重来（`IconCache.setDarkSurface`）。
它挂在 `NSApp.effectiveAppearance` 上而不是 `applyAppearance()` 里 —— 「跟随系统」时我们
从不赋值，那条路只有这里收得到。

### 设置窗口

设置界面在 `QuickUI`，但插件实例与系统能力（登录项、快捷键、权限）只有组装层看得到，
所以用 `SettingsDataSource` 协议把两边隔开 —— **`QuickUI` 因此既不认识插件，
也不认识 `QuickPlatform`**，依赖方向保持不变。由 `AppCore` 实现协议。

`SettingsStore`（持久化）由 `AppCore` 持有并注入，**不是单例**。

设置窗口与 AI 网页窗口是「像普通窗口那样被对待」的两种界面，但**记账只有一处**：
`ActivationPolicyKeeper`。谁在场谁 `retain`，最后一个人走时恢复 `.accessory`。
accessory 应用不进 Dock、也不进 ⌘Tab 切换器 —— 用户一旦从这两种窗口切走，就再也找不
回来它们。按**持有者集合**记账而不是计数器，是因为两者可能同时开着：谁先关都不能把
对方的 Dock 身份带走。

### 键盘输入归属

| 按键 | 谁处理 | 为什么 |
| --- | --- | --- |
| Esc | `PalettePanel.sendEvent` → `PaletteCoordinator.handleEscape` | 要在 field editor 之前拦下。三层优先级：插件模式退回搜索 → 搜索框有内容则清空 → 都空才收起面板 |
| 裸退格 | `PalettePanel.sendEvent` | 搜索框为空时退回上一层 |
| ⌘W | `PalettePanel.sendEvent` → `onClose` | 始终是「收起面板」。**不与 Esc 共用回调**，否则会退化成「清空搜索框」 |
| 其他 ⌘ 组合键 | `PalettePanel.sendEvent` | 要在 field editor 之前拦下 |
| ↑ ↓ / 回车 | `PalettePanel.sendEvent` → `PaletteSelection` | 同上：焦点在搜索框里，SwiftUI 层收不到 |
| 文本输入 | 搜索框（SwiftUI `TextField`） | 它就是焦点 |
| ⌘A / ⌘C / ⌘V / ⌘X / ⌘Z | 主菜单的编辑菜单项 | **不是文本框自己实现的**：它们是菜单项的 key equivalent，由 AppKit 沿响应链派发 `selectAll:` / `copy:` / `paste:`。没有主菜单这些组合键就没人处理 —— 而 accessory 应用默认没有主菜单，见 `MainMenu` |
| 点击行 / 悬停 | `ResultListView` | 鼠标路径本来就在 SwiftUI 里 |

中文输入法用户按 ⌥Space 时往往还停在拼音状态，敲出来的是拼音串。设置页的「强制键盘布局」
让面板打开期间切到指定布局（通常是 ABC）、关闭后还原；切换时机挂在协调器的
`onPanelWillShow` / `onPanelDidHide` 上，由 `AppCore` 接线。它和 `HotKeyService` 一样
必须走 Carbon 的 Text Input Source API（`TIS*`）—— AppKit / SwiftUI 里没有任何办法
枚举或程序化切换系统输入源，理由与全局热键同属「有意的能力缺口依赖」。

`PaletteSelection` 是一个**不持有窗口**的 `@Observable` 对象，所以被 SwiftUI 观察是
安全的 —— 会与 AttributeGraph 死循环的是持有 `NSPanel` 的协调器本身。

### 三个 MUST 级别的窗口配置

这三个值改动会导致真实故障，注释已写在代码里：

```swift
hidesOnDeactivate = false                  // 否则菜单栏点击后应用失活，面板立刻被隐藏
styleMask: [.borderless, .nonactivatingPanel]  // 非激活面板，不抢别的应用的焦点
collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
```

显隐要走 `PaletteCoordinator.toggle()` / `show()` / `hide()`。`show()` 会记下当前前台应用，
`hide(restoreFocus: true)` 会把焦点还回去 —— 这是它体感好的关键，别绕过去直接操作 panel。

### 面板的两种模式

面板支持**搜索模式**和**插件模式**，通过 `PaletteMode`（`@Observable`）桥接状态：

- **搜索模式**（默认）：搜索框 + 结果列表，用户输入关键词查找插件功能。
  Esc 在搜索框有内容时**只清空输入**，空输入时才收起面板 —— 关掉整个面板的代价太大，
  而用户按 Esc 时多半只是想重打一个关键词。
- **插件模式**：用户选中一个插件后，面板切换为该插件的完整视图（`makeView()`）。
  头部变为返回按钮 + 插件名称 + 分离按钮。Esc 返回搜索模式（此时屏幕上没有搜索框，
  所以不存在「清空」这一层）。

`PaletteMode` 不持有 `NSPanel`，只持有纯状态（`activePluginID`、`context`、插件元信息），
所以被 SwiftUI 观察是安全的。协调器在 `navigate` / `popToRoot` 时同步更新它。

### 分离窗口

插件面板可以通过 ⌘D 或头部分离按钮分离为独立 `NSWindow`。
`PluginPanelController` 管理分离窗口，策略如下：

- **单例**：同一插件只允许一个分离窗口，再次分离时聚焦已有窗口。
- **尺寸记忆**：关闭时保存到 `UserDefaults`，下次打开恢复。
- **落在鼠标所在的那块屏上**：屏幕按 `NSEvent.mouseLocation` 选（`ScreenPlacement`），
  与主面板同一套判定。**不要用 `NSWindow.center()`** —— 它落在主屏，而主屏是系统设置里
  指定的那一块，鼠标在内建屏上、主屏是外接显示器时窗口就会凭空跳过去。
  有源窗口且源窗口也在这块屏上时贴着它偏移 30，否则居中；两种落点都夹在这块屏的可用区域内。
- **主面板行为**：分离后主面板 `popToRoot()` 回到搜索模式并隐藏。

分离事件通过 `DetachPanelEvent` → `EventBus` → `AppCore.detachPlugin()` 路由，
`AppCore` 从插件实例获取视图并交给 `PluginPanelController` 创建窗口。

### 分离窗口与主面板是两个互不相干的窗口

这一条是行为契约，不是实现细节：

- 唤出主面板（⌥Space）**不会**把分离窗口带到前台。用户按快捷键是想找东西，不是想切回
  某个已经开着的页面。实现上靠分离窗口的 `.nonactivatingPanel`：非激活面板不参与应用
  激活时的窗口排序，所以 `NSApp.activate` 不会把它一起抬起来。
- **AI 网页窗口不适用这一条**，它是刻意的：那块页面是用户会持续使用的东西，必须能在
  ⌘Tab / Mission Control 里被找回来（详见「AI 网页窗口」一节）。所以唤出主面板时它会
  一起到前台 —— 面板本身是 `.floating`，仍然盖在它上面。
- 关掉主面板不影响分离窗口；反之亦然。
- 也正因为两者独立，**窗口控制必须留在窗口自己身上**，不能只挂在主面板的头部 ——
  用户不看主面板时那些按钮就够不着了。具体放在哪，见下面两节。

`AppCore` 在退出时统一收掉它们（`closeAll()`）；插件停用时由插件自己收掉，
`AIPlugin.deactivate()` 就是这样做的。

### 分离窗口的控制在它的标题栏里

分离窗口有自己的自绘标题栏，所以置顶 / 关闭**就长在标题栏右侧**（`BarButton` 的
`.icon` 样式，尺寸走 `Size.windowControlButton` / `Typography.windowControlIcon`，
比底栏按钮小一档），刷新保留 ⌘R。不用悬浮胶囊，是因为那个浮层带来的一整套交互
（可拖、可折叠、位置要持久化）只在「窗口没有自己的边框」时才值得付。

**标题栏必须自己实现拖拽。** `isMovableByWindowBackground` 在 SwiftUI 内容上靠不住：
窗口是看 `hitTest` 命中的那个视图的 `mouseDownCanMoveWindow` 决定拖不拖的，而面板里
铺满的 vibrancy 背景（一个真实的 `NSVisualEffectView`）与 hosting view 都不返回它 ——
表现就是**窗口拖不动**。所以标题栏的身份区挂了 `WindowDragArea`（一个只做
`performDrag` 的真实 `NSView`）。它**只铺在按钮左边**：它是个真实的 `NSView`，
铺到按钮上面会把点击吃掉。

**刷新是真的重建**：`PluginPanelController` 存的是视图工厂（`viewProvider`）而不是
建好的视图，所以刷新会重新走一遍插件的 `makeView()`，而不是重画一份旧状态。

### AI 网页窗口：普通窗口 + 悬浮胶囊

`AIWebViewWindowManager` 每个 Provider 一个独立窗口，**关闭只是隐藏**（保持登录态与
会话历史），销毁走显式命令。

- **它是普通窗口，不是非激活面板。** 这一条决定它能不能被找回：非激活面板不进
  ⌘Tab / Mission Control，用户切走之后只剩「再从面板点一次」这一条路。普通窗口能成为
  key、也能成为 main。
- **可见期间占用 Dock 身份**：accessory 应用不在切换器里，所以只要还有一个可见窗口，
  就通过 `ActivationPolicyKeeper` 暂时变成 `.regular`；最后一个窗口隐藏或销毁时交还。
  隐藏也要交还 —— 窗口看不见时没有「找回来」的需求，Dock 里挂一个点开什么都没有的图标
  只会更困惑。
- **唤起时到最前**要三句一起：`NSApp.activate(ignoringOtherApps:)` +
  `makeKeyAndOrderFront` + `orderFrontRegardless`。少一句就会「唤醒了却不在最前面」，
  新建的窗口尤其容易。

窗口里唯一常驻的控件是悬浮胶囊（它的内容是一整块网页，没有自己的边框）：

[`FloatingCapsuleView`](../Packages/QuickUI/Sources/QuickUI/Windows/FloatingCapsuleView.swift)
参考 Fasty 的 `capsuleInjectionScript`：

- **收起态**只显示抓手与展开箭头（22px 圆钮、2px 内边距、全圆角），展开后是
  置顶 / 刷新 / 外部打开 / 关闭（关闭前有一条分组线）。默认收起是为了不挡页面内容。
- **可拖拽**：位移超过 3px 才算拖拽，落点夹在窗口内（优先保证左下不出界），
  松手把位置写进 `UserDefaults`，同一个 Provider 的窗口下次回到原处。
- **叠在内容之上**，不参与网页的布局 —— 它不能依赖页面 DOM（页面是第三方的，
  随时会变）。
- 几何与配色全部来自 `DesignTokens.Size.Capsule` / `DesignTokens.Colors.capsule*`。

### 不要给协调器加 `@Observable`

`PaletteCoordinator` 顶部有注释说明原因：宿主 `NSPanel` 里的 SwiftUI 视图一旦观察它，
会与 AttributeGraph 形成重建死循环，CPU 100%。**这是本项目已经踩过并修好的坑**
（见提交 `304af38`）。搜索文本等易变状态放在 `PaletteRootView` 的 `@State` 里。

### 位置

面板定位到**光标所在屏幕**（不是主屏）的中上方，距可见区顶部
`DesignTokens.Size.paletteTopMarginFraction`（0.18）比例处，水平居中。

「光标在哪块屏」的判定只有一处实现：`ScreenPlacement`。主面板与分离窗口都用它 ——
`NSScreen.main` 是系统设置里指定的主屏，跟用户此刻在看哪块屏没有关系，谁拿它定位，
谁就会在双屏下把窗口开到另一块屏上去。

---

## 7. 权限

辅助功能与屏幕录制权限走
[`PermissionService`](../Packages/QuickPlatform/Sources/QuickPlatform/Permissions/PermissionService.swift)。

- **不要散落的 `AXIsProcessTrusted()` 调用。** 统一走 Service，这样日志与提示语一致。
- 权限**按需申请**，不要在启动时一次性全要 —— 那会让首次体验变成一串弹窗。
- 申请前后都要 `QuickLog`，用户报「功能不工作」时第一条要查的就是权限。
- 授权状态会随重建签名失效（TCC 认签名）。开发期频繁重建导致权限反复丢失是正常的，
  不是代码 bug。
- **拖拽授权面板吸附在系统设置窗口正下方，宽度跟随右侧内容区**（设置窗口宽度 −
  `systemSettingsSidebar`，屏幕装不下时才收窄），高度按这个宽度量出来。面板是无边框窗口，
  **四角必须自己裁圆**（`clipShape(Radius.panel)`）—— 否则 vibrancy 会铺满矩形四角，
  取自窗口 alpha 的阴影也跟着变方。
