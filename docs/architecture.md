# 架构

本文件回答「东西挂在哪、谁拥有谁、什么时候被创建」。写代码风格看
[standards.md](standards.md)。

---

## 1. 分层与依赖方向

```
┌──────────────────────────────────────────────────────────┐
│  Quick（应用目标）                                        │
│  QuickApp / AppDelegate / AppCore / StatusItemController  │
│  —— 唯一的 composition root，唯一 import Module* 的地方    │
└───────────────────────┬──────────────────────────────────┘
                        │
        ┌───────────────┼───────────────┐
        ▼               ▼               ▼
  ┌──────────┐   ┌───────────┐   ┌──────────────┐
  │ Module*  │   │  QuickUI  │   │ QuickPlatform│   （17 个 / 1 个 / 1 个）
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
  和 `SwiftUI` 的 `AnyView` 类型 —— `QuickModule.makeView()` 签名需要）。
- `QuickUI` / `QuickPlatform` 依赖 `QuickCore`，**不**依赖任何模块。
- `Module*` 依赖 `QuickCore` + `QuickUI`，需要系统能力时再加 `QuickPlatform`。
  **模块之间永不互相依赖。**
- `Quick/` 依赖全部。只有它能 import 各模块。

**为什么模块间不能互相依赖：** 20 个模块两两依赖会变成一张网，任何改动都会波及全仓，
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
| `launchAtLogin` | `LaunchAtLogin` | 登录项（`SMAppService`） |
| `statusItemController` | `StatusItemController` | 菜单栏图标与菜单 |
| `modules` | `[any QuickModule]` | 全部 17 个模块实例 |
| `subscriptions` | `[EventSubscription]` | 事件订阅句柄（不持有就会被释放） |

### `start()` 的固定顺序

顺序是有意的，改动前想清楚依赖：

1. `registerModules()` —— 组装模块（**唯一实例化模块的地方**）
2. `paletteCoordinator.setModules(modules)` —— 让面板能搜索
3. `wireEventBus()` —— 订阅事件，把事件接到协调器/剪贴板/HUD
4. 热键：设 `onTogglePalette` 回调 → `hotKeyService.start()`
5. `statusItemController.install()` —— 菜单栏图标
6. `observeDebugWakeSignals()` —— 调试用分布式通知
7. `Task { await appIndex.refresh() }` —— **异步**扫描应用，不阻塞启动
8. 对每个已启用模块调用 `activate()`
9. 若启动参数带 `-showPalette`，立即显示面板

退出走 `prepareForTermination()`：停热键 → 摘菜单栏 → `deactivate()` 各模块 →
`EventBus.shared.removeAll()`。

### 新增状态的规矩

- 新的长生命周期状态**挂到 `AppCore` 上**，在 `start()` 里接线。
- **绝不**另起一个 `static let shared` 单例来放状态。目前只有两个单例：
  `AppCore.shared` 和 `EventBus.shared`，两者都是有意的，不要加第三个。
- 视图**不要**直接拿 `AppCore`。视图通过 `@Environment` 拿协调器，或通过构造参数注入
  依赖（例如 `LauncherModule(appIndex:)`）。

---

## 3. 模块契约：`QuickModule`

[`Packages/QuickCore/Sources/QuickCore/Protocols/QuickModule.swift`](../Packages/QuickCore/Sources/QuickCore/Protocols/QuickModule.swift)

```swift
@MainActor
public protocol QuickModule: AnyObject, Sendable {
    static var id: String { get }        // 全局唯一主键：事件路由 + 设置存储
    static var name: String { get }      // 出现在搜索结果与设置页
    static var icon: String { get }      // SF Symbol 名
    var isEnabled: Bool { get set }
    func searchItems(query: String) async -> [SearchableItem]
    func makeView() -> AnyView           // 面板内的模块主视图
    func makeSettingsView() -> AnyView?  // 设置页；无设置返回 nil
    func activate()                      // 启动 / 启用时
    func deactivate()                    // 退出 / 禁用时
}
```

协议提供了默认实现：`isEnabled` 默认 `true`、`makeSettingsView` 默认 `nil`、
`searchItems` 默认空、`activate`/`deactivate` 默认无操作。**只实现你需要的那些**，
不要写空实现占位。

### 不变量

- **`static var id` 一旦发布就不能改。** 它是 `SettingsKey.moduleEnabled(id)` 的键，
  改了等于用户设置丢失。
- **`searchItems` 必须是纯查询。** 不要在里面激活模块、写盘、发网络请求、改 `isEnabled`。
  它可能在每次按键时被调用（虽然并发，但不是免费的）。要缓存就在 `activate()` 里预热。
- **`searchItems` 必须尊重防抖与取消。** 调用方（`PaletteCoordinator`）只在防抖后调用，
  但模块内部若有昂贵准备，要检查 `Task.isCancelled`。
- **`makeView()` 返回的视图不要持有 `AppCore`。** 需要能力就通过模块构造器注入。
- **`activate()` / `deactivate()` 必须成对且幂等。** 模块可能被反复启停。
- **`deactivate()` 里要落盘。** 未保存的运行时状态在退出时就丢了。

### 注册流程

模块**不自注册**。加一个模块要做四件事：

1. 写 `<Name>Module.swift` 实现协议。
2. 在 `AppCore.registerModules()` 里 `modules.append(...)`。
3. 在 `project.yml` 的 `packages:` 加路径、在 `Quick` target 的 `dependencies:` 加
   `- package: Module<Name>`，然后 `xcodegen generate`。
4. 在 `docs/features/<id>.md` 写下这个模块的不变量。

第 2 步是唯一实例化点。如果你发现自己在别处 `new` 一个模块，那就是错了。

---

## 4. `EventBus`：模块间唯一的通信方式

[`Packages/QuickCore/Sources/QuickCore/Events/EventBus.swift`](../Packages/QuickCore/Sources/QuickCore/Events/EventBus.swift)

```swift
@MainActor public final class EventBus: Sendable {
    public static let shared: EventBus
    public func post<E: ModuleEvent>(_ event: E)
    @discardableResult
    public func on<E: ModuleEvent>(_ type: E.Type, handler: @escaping (E) -> Void) -> EventSubscription
    public func unsubscribe(_ subscription: EventSubscription)
    public func removeAll()
}
```

事件是 `Sendable` 的值类型，自带 `static var name` 作为路由键。内置事件：

| 事件 | 用途 |
| --- | --- |
| `NavigateEvent` | 让面板跳到某个模块（可带 query 上下文） |
| `ShowPaletteEvent` / `HidePaletteEvent` | 显隐面板 |
| `CopyToClipboardEvent` | 请求写剪贴板 |
| `ShowHUDEvent`（+ `HUDTone`） | 请求弹一条提示 |

### 不变量

- **必须保存 `EventSubscription`。** 它是句柄，返回值丢弃就等于随 ARC 一起取消订阅。
  保存到 `AppCore.subscriptions` 或模块自己的属性里，并在 `deactivate()` 时释放。
- **事件处理器在主 actor 上同步执行。** 不要在里面做重活；需要异步就 `Task { }`。
- **事件名（`static var name`）是全局命名空间**，用 `quick.<区域>.<动作>` 格式，
  不要和别的模块撞。
- **不要用 `EventBus` 做请求-响应。** 它没有返回值。需要拿结果就直接调那个模块 ——
  但那种情况说明这两个模块的边界画错了，先重新想。

---

## 5. 数据模型

### `SearchableItem`

[`Packages/QuickCore/Sources/QuickCore/Models/SearchableItem.swift`](../Packages/QuickCore/Sources/QuickCore/Models/SearchableItem.swift)

```swift
public struct SearchableItem: Identifiable, Sendable {
    public let id: String
    public let moduleID: String
    public let title: String
    public let subtitle: String?
    public let icon: String
    public let iconType: IconType      // .symbol / .appIcon(path) / .image(name)
    public let relevance: Double       // 0...1，聚合后按它降序排
    public let shortcutHint: String?
    public let action: @MainActor () -> Void
}
```

- `Hashable` **只基于 `id`**。所以 `id` 必须在模块内唯一且稳定；重复 id 会让列表错乱。
- `relevance` 是跨模块比较的**唯一**依据。`String.fuzzyScore` 给出的阶梯是：
  完全匹配 `1.0`、前缀匹配 `0.9`、包含匹配 `0.7`、子序列模糊匹配 `0.4`、不匹配 `0`
  （见 `QuickCore/Extensions/StringExtensions.swift`）。模块可以在这个基础上叠加自己的
  权重（`LauncherModule` 就是 `fuzzyScore * 0.7 + 使用频率 * 0.3`），
  但**不要所有结果都给 `1.0`** —— 那等于放弃了排序，列表顺序会变成随机。
- `action` 在按下回车/点击时于主 actor 执行。它应该**只发事件或调用已注入的依赖**，
  不要直接 `NSWorkspace` 之类的全局调用（除了启动应用这种确实没有别的写法的情况）。

### 持久化用 `AppPaths`

所有落盘路径走
[`AppPaths`](../Packages/QuickPlatform/Sources/QuickPlatform/System/AppPaths.swift)：
`applicationSupport()` / `caches()` / `logs()` / `moduleData(_:)`。
**不要自己拼 `~/Library/...`** —— 路径集中在一处才能统一改动（例如将来给 Debug 配独立
bundle id 时，只需要改 `AppPaths` 一个地方）。

---

## 6. 面板与窗口

`PaletteCoordinator` 拥有面板，负责显隐、定位、模式切换，**不含任何业务逻辑**。

### 三个 MUST 级别的窗口配置

这三个值改动会导致真实故障，注释已写在代码里：

```swift
hidesOnDeactivate = false                  // 否则菜单栏点击后应用失活，面板立刻被隐藏
styleMask: [.borderless, .nonactivatingPanel]  // 非激活面板，不抢别的应用的焦点
collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
```

显隐要走 `PaletteCoordinator.toggle()` / `show()` / `hide()`。`show()` 会记下当前前台应用，
`hide(restoreFocus: true)` 会把焦点还回去 —— 这是它体感好的关键，别绕过去直接操作 panel。

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
