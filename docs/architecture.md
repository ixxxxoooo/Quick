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
4. 热键：设 `onTogglePalette` 回调 → `hotKeyService.start()`
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
    static var id: String { get }        // 全局唯一主键：事件路由 + 设置存储
    static var name: String { get }      // 出现在搜索结果与设置页
    static var icon: String { get }      // SF Symbol 名
    var isEnabled: Bool { get set }
    func searchItems(query: String) async -> [SearchableItem]
    func makeView() -> AnyView           // 面板内的插件主视图
    func makeSettingsView() -> AnyView?  // 设置页；无设置返回 nil
    func activate()                      // 启动 / 启用时
    func deactivate()                    // 退出 / 禁用时
}
```

协议提供了默认实现：`isEnabled` 默认 `true`、`makeSettingsView` 默认 `nil`、
`searchItems` 默认空、`activate`/`deactivate` 默认无操作。**只实现你需要的那些**，
不要写空实现占位。

### 不变量

- **`static var id` 一旦发布就不能改。** 它是 `SettingsKey.pluginEnabled(id)` 的键，
  改了等于用户设置丢失。
- **`searchItems` 必须是纯查询。** 不要在里面激活插件、写盘、发网络请求、改 `isEnabled`。
  它可能在每次按键时被调用（虽然并发，但不是免费的）。要缓存就在 `activate()` 里预热。
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
- `relevance` 是跨插件比较的**唯一**依据。`String.fuzzyScore` 给出的阶梯是：
  完全匹配 `1.0`、前缀匹配 `0.9`、包含匹配 `0.7`、子序列模糊匹配 `0.4`、不匹配 `0`
  （见 `QuickCore/Extensions/StringExtensions.swift`）。插件可以在这个基础上叠加自己的
  权重（`LauncherPlugin` 就是 `fuzzyScore * 0.7 + 使用频率 * 0.3`），
  但**不要所有结果都给 `1.0`** —— 那等于放弃了排序，列表顺序会变成随机。
- `action` 在按下回车/点击时于主 actor 执行。它应该**只发事件或调用已注入的依赖**，
  不要直接 `NSWorkspace` 之类的全局调用（除了启动应用这种确实没有别的写法的情况）。

### 持久化用 `AppPaths`

所有落盘路径走
[`AppPaths`](../Packages/QuickPlatform/Sources/QuickPlatform/System/AppPaths.swift)：
`applicationSupport()` / `caches()` / `logs()` / `pluginData(_:)`。
**不要自己拼 `~/Library/...`** —— 路径集中在一处。`AppPaths` 已按
`Bundle.main.bundleIdentifier` 分目录，Debug（`.dev`）与 Release 互不污染。

---

## 6. 面板与窗口

`PaletteCoordinator` 拥有面板，负责显隐、定位、模式切换，**不含任何业务逻辑**。

### 设置窗口

设置界面在 `QuickUI`，但插件实例与系统能力（登录项、快捷键、权限）只有组装层看得到，
所以用 `SettingsDataSource` 协议把两边隔开 —— **`QuickUI` 因此既不认识插件，
也不认识 `QuickPlatform`**，依赖方向保持不变。由 `AppCore` 实现协议。

`SettingsStore`（持久化）由 `AppCore` 持有并注入，**不是单例**。

### 键盘输入归属

| 按键 | 谁处理 | 为什么 |
| --- | --- | --- |
| Esc / 裸退格 / ⌘ 组合键 | `PalettePanel.sendEvent` | 要在 field editor 之前拦下 |
| ↑ ↓ / 回车 | `PalettePanel.sendEvent` → `PaletteSelection` | 同上：焦点在搜索框里，SwiftUI 层收不到 |
| 文本输入 | 搜索框（SwiftUI `TextField`） | 它就是焦点 |
| 点击行 / 悬停 | `ResultListView` | 鼠标路径本来就在 SwiftUI 里 |

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
- **插件模式**：用户选中一个插件后，面板切换为该插件的完整视图（`makeView()`）。
  头部变为返回按钮 + 插件名称 + 分离按钮。Esc 返回搜索模式。

`PaletteMode` 不持有 `NSPanel`，只持有纯状态（`activePluginID`、`context`、插件元信息），
所以被 SwiftUI 观察是安全的。协调器在 `navigate` / `popToRoot` 时同步更新它。

### 分离窗口

插件面板可以通过 ⌘D 或头部分离按钮分离为独立 `NSWindow`。
`PluginPanelController` 管理分离窗口，策略如下：

- **单例**：同一插件只允许一个分离窗口，再次分离时聚焦已有窗口。
- **尺寸记忆**：关闭时保存到 `UserDefaults`，下次打开恢复。
- **主面板行为**：分离后主面板 `popToRoot()` 回到搜索模式并隐藏。

分离事件通过 `DetachPanelEvent` → `EventBus` → `AppCore.detachPlugin()` 路由，
`AppCore` 从插件实例获取视图并交给 `PluginPanelController` 创建窗口。

### 分离窗口与主面板是两个互不相干的窗口

这一条是行为契约，不是实现细节：

- 唤出主面板（⌥Space）**不会**把分离窗口或 AI 窗口带到前台。用户按快捷键是想找东西，
  不是想切回某个已经开着的页面。实现上靠 `.nonactivatingPanel`：非激活面板不参与
  应用激活时的窗口排序，所以 `NSApp.activate` 不会把它们一起抬起来。
- 关掉主面板不影响分离窗口；反之亦然。
- 也正因为两者独立，**窗口控制必须留在窗口自己身上**（下一小节的悬浮胶囊），
  不能只挂在主面板的头部 —— 用户不看主面板时那些按钮就够不着了。

`AppCore` 在退出时统一收掉它们（`closeAll()`）；插件停用时由插件自己收掉，
`AIPlugin.deactivate()` 就是这样做的。

### 悬浮胶囊：分离窗口唯一的常驻控件

[`FloatingCapsuleView`](../Packages/QuickUI/Sources/QuickUI/Windows/FloatingCapsuleView.swift)
是分离窗口右上角的悬浮操作条，参考 Fasty 的 `capsuleInjectionScript`：

- **收起态**只显示抓手与展开箭头（22px 圆钮、2px 内边距、全圆角），展开后是
  置顶 / 刷新 / 关闭（关闭前有一条分组线）。默认收起是为了不挡插件内容。
- **可拖拽**：位移超过 3px 才算拖拽，落点夹在窗口内（优先保证左下不出界），
  松手把位置写进 `UserDefaults`，同一个插件的窗口下次回到原处。
- **叠在内容之上**，不参与插件视图的布局 —— 否则「每个插件都能拿到窗口控制」
  就只在插件自己留了白的情况下成立。
- **刷新是真的重建**：`PluginPanelController` 存的是视图工厂（`viewProvider`）而不是
  建好的视图，所以刷新会重新走一遍插件的 `makeView()`，而不是重画一份旧状态。

几何与配色全部来自 `DesignTokens.Size.Capsule` / `DesignTokens.Colors.capsule*`。
插件窗口与 AI 窗口共用同一个实现 —— 想改胶囊的样子，只改一处。

### 不要给协调器加 `@Observable`

`PaletteCoordinator` 顶部有注释说明原因：宿主 `NSPanel` 里的 SwiftUI 视图一旦观察它，
会与 AttributeGraph 形成重建死循环，CPU 100%。**这是本项目已经踩过并修好的坑**
（见提交 `304af38`）。搜索文本等易变状态放在 `PaletteRootView` 的 `@State` 里。

### 位置

面板定位到**光标所在屏幕**（不是主屏）的中上方，距可见区顶部
`DesignTokens.Size.paletteTopMarginFraction`（0.18）比例处，水平居中。

---

## 7. 权限

辅助功能与屏幕录制权限走
[`PermissionService`](../Packages/QuickPlatform/Sources/QuickPlatform/Permissions/PermissionService.swift)。

- **不要散落的 `AXIsProcessTrusted()` 调用。** 统一走 Service，这样日志与提示语一致。
- 权限**按需申请**，不要在启动时一次性全要 —— 那会让首次体验变成一串弹窗。
- 申请前后都要 `QuickLog`，用户报「功能不工作」时第一条要查的就是权限。
- 授权状态会随重建签名失效（TCC 认签名）。开发期频繁重建导致权限反复丢失是正常的，
  不是代码 bug。
