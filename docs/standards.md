# Swift 与 SwiftUI 编码规范

本文件回答「这行代码该怎么写」。架构与所有权的问题看
[architecture.md](architecture.md)，测试的门槛看 [testing.md](testing.md)。

规范的目标有三个，且优先级依次递减：**正确**、**可读**、**快**。三者冲突时按这个顺序取舍 ——
但「快」的含义是在正确的抽象下不浪费，而不是为了微优化牺牲可读性。

---

## 1. 命名

### 1.1 类型后缀说明它「是什么」

后缀不是装饰，它承诺了一类职责。写之前先确定你要写的是哪一种：

| 后缀 | 含义 | 例子 |
| --- | --- | --- |
| `Plugin` | 一个功能插件，实现 `QuickPlugin` | `ClipboardPlugin` |
| `Store` | 持久化某类数据的读写者，负责落盘 | `RankingStore`、`ClipboardStore` |
| `Service` | 对系统或网络的封装，无 UI | `PasteboardService`、`HotKeyService` |
| `Coordinator` | 编排一组视图/窗口的生命周期与路由 | `PaletteCoordinator` |
| `Controller` | 拥有一个 AppKit 窗口并驱动它 | `HUDController`、`StatusItemController` |
| `Engine` | 纯计算，输入到输出，无状态副作用 | `CalcEngine` |
| `Index` | 内存中的可查询集合，可刷新 | `AppIndex` |
| `Scanner` | 一次性枚举某个外部数据源的遍历器 | `ProcessScanner` |
| `View` | SwiftUI 视图 | `SearchFieldView` |
| `Session` | 一次交互过程的会话状态 | `FileSearchSession` |
| `Tool` | DevTools 下的一个独立小工具 | `TextDiffTool` |

**语义正确优先于后缀一致性。** 没有合适后缀就新增一个并在本表登记，绝不要为了凑后缀把一个
类型改名成不准确的名字。

### 1.2 其余命名规则

- **类型** 用 `UpperCamelCase`；**方法与属性** 用 `lowerCamelCase`；两者都要读起来像话。
- **布尔量** 读起来必须是一个断言：`isVisible`、`hasAccessibilityPermission`、
  `shouldRestoreFocus`。不要用 `flag`、`enable`（名词/动词混淆）。
- **突变方法与它的非突变版**：非突变用过去分词（`sorted()`），突变用祈使式（`sort()`）。
- **不要 `get` 前缀**，不要匈牙利命名，不要在名字里重复类型（`let clipboardEntryEntry`）。
- **缩写按 Swift 惯例**：`id` / `URL` / `ID` 作为类型名全大写，作为属性名 `id` / `url`。
- **泛型参数**要有意义（`Element`、`Result`），单字母只在一眼能懂时用（`T` 于一个类型参数）。
- **避免 `Manager`。** 它什么也没说。先问清它到底是 `Store`、`Service`、`Coordinator`
  还是 `Controller`，再用那个名字。

---

## 2. 并发（Swift 6 语言模式）

严格并发是 `complete`，数据竞争是**编译错误**。规矩如下。

### 2.1 隔离默认在主 actor

- UI 相关类型一律 `@MainActor`：视图、协调器、控制器、插件。
- `QuickPlugin` 协议本身是 `@MainActor`，所以插件实现天然主线程隔离。
- 跨 actor 传递的模型类型必须是 `Sendable`。优先用 `struct` + `let` 属性 —— 它是自动
  `Sendable` 的，不需要任何标注。

### 2.2 重活离开主线程

主线程只做「组装视图」和「切换状态」。任何可能超过一帧的活都必须离开主线程：

```swift
// ✅ 磁盘枚举、网络、解析：nonisolated + Task.detached
nonisolated func scanApplications() async -> [AppEntry] {
    // 纯计算 / IO，不碰任何主 actor 状态
}

// 调用侧：结果回到主 actor 再赋值
let entries = await Task.detached { await scanner.scanApplications() }.value
self.entries = entries
```

- **不要新增 actor。** 本项目只有「主 actor」与「无隔离」两档。加第三个 actor 意味着你还没
  想清楚所有权；先用 `nonisolated` 函数 + `Sendable` 数据解决。
- **不要用 `DispatchQueue`。** 尤其不要 `DispatchQueue.main.async` 来回切 —— 那是 Swift 5 的写法。
  用 `Task { @MainActor in ... }`。
- **不要 `@unchecked Sendable`。** 唯一的例外是已经存在的 Carbon C 回调跳板
  （`HotKeyService._instance`），它靠「只在主线程访问」保证安全，且必须写明这一行注释。

### 2.3 取消与生命周期

- 长任务持有 `Task` 句柄，并在新输入到来或视图消失时 `cancel()`。搜索类功能必须防抖 + 取消，
  否则每次按键都会堆积一次全插件扫描。
- `withTaskGroup` 的并发分支里不要捕获 `self` 的可变状态；让每个分支只做纯计算并返回结果。
- 定时器优先用 `Task` + `Task.sleep`，而不是 `Timer`；用了 `Timer` 就在 `deinit`/退出路径上
  `invalidate()`。

### 2.4 不要造成 AttributeGraph 死循环

这个坑本项目已经踩过两次，写 UI 状态时务必记住：

- **不要用 `@Observable` 标记持有 `NSPanel` 的协调器。** 宿主窗口里的 SwiftUI 视图一旦观察
  该对象，就会与 AttributeGraph 形成重建循环，CPU 打满。`PaletteCoordinator` 顶部有注释说明，
  不要「顺手补上 `@Observable`」。
- **不要在 `body` 里创建新的 `NSImage` 或调用会触发状态变更的昂贵 API。** 用 `@State` +
  `.onAppear` 缓存一次（参考 `ResultListView.AppIconImage`）。
- 视图状态用 `@State` / `@Binding` 局部化，不要为了少写绑定把状态提升到协调器上。

---

## 3. 性能预算

启动器是「按一下就要出现」的东西，延迟直接等于体感差。预算如下。

| 操作 | 预算 | 说明 |
| --- | --- | --- |
| 面板 `show()` 到可见 | < 100 ms | 首次可放宽到 150 ms（含面板构建） |
| 一次按键到结果刷新 | < 50 ms | 80 ms 防抖之后，聚合搜索本身要远小于此 |
| 空闲 CPU | ≈ 0 % | 面板显示时也不得持续 > 5 % |
| 冷启动到托盘图标出现 | < 400 ms | 应用扫描必须异步，不阻塞启动 |
| 内存常驻 | < 150 MB | 图标缓存是主要占用，注意上限 |

硬性规则：

- **不要在 `body` 里做 IO。** 不要读文件、不要查磁盘、不要发网络请求、不要创建 `NSImage`。
- **不要在循环里做模糊匹配。** 名称规范化（折叠大小写/变音符号/全角）与拼音转写都有成本，
  要么预处理时算好，要么每次刷新算一次，绝不要每次按键重算。候选多的时候用
  `MatchQuery` + `MatchText` 把两边各准备一遍：查询词每次按键折叠一次，候选跟着数据一起存
  （`AppEntry.matchText` 就是这么做的）。候选只有个位数时，`String.fuzzyScore` 就够了。
- **图标走 `IconCache`。** 不要直接 `NSWorkspace.shared.icon(forFile:)` 到视图里 ——
  每次都新建 `NSImage`，既慢又会触发上一节的死循环。
- **列表用 `LazyVStack` / `LazyHStack`。** 不要用 `VStack` 铺可能变长的集合。
- **搜索是并发的，但结果要排序后再进视图。** 不要把排序放在 `body` 里。
- 任何「加一行缓存」的优化都要先有测量。没有测量数据的优化是猜的。

---

## 4. 注释与文档

注释是最容易被滥用的东西，规则从紧：

- **注释解释「为什么」，永远不解释「什么」。** 代码已经说了「什么」。
- **只在两种情况下写注释**：有外部约束（系统 bug、API 反直觉、性能陷阱），
  或者有必须保持的不变量。其余情况请改用更好的命名或拆函数。
- **每个公开类型、每个公开方法写文档注释**（`///`）。这是 API 契约，不是解释。
  私有实现**不需要**逐行注释。
- **绝不允许连续两行注释，也不允许扩展成注释块。** 一行说不完，就说明该提取一个函数、
  常量或类型，用名字把话说清楚。
- **一行上限 120 字符。** 与其换行，不如删减。
- **不要注释你刚做的改动。** 「这里加了判断」这类信息属于提交信息，不属于代码。
- **中文注释，英文标识符。** 项目内注释使用中文（与现有代码一致）；类型名、方法名、属性名、
  日志的 `category`、以及所有提交信息使用英文。

示例：

```swift
// ✅ 说明外部约束，一行，不多不少
// 菜单栏点击后应用会失活；默认 true 会让面板立刻被隐藏。
hidesOnDeactivate = false

// ✅ 说明必须保持的不变量
/// 面板宽度。设计与 Tinycast 对齐，改动这里要同步 docs/ui.md。
static let panelWidth: CGFloat = 750

// ❌ 复述代码
// 设置 hidesOnDeactivate 为 false
hidesOnDeactivate = false

// ❌ 注释块，且是给 reviewer 看的
// 我们之前用 @Observable，导致 CPU 100%，
// 所以现在改成普通的 class。
// 这样就不会有 AttributeGraph 死循环了。
```

---

## 5. 格式与排版

- **缩进 4 空格**，无制表符。行长软上限 110，硬上限 130。
- 跟随周围代码的排版风格，不要在评审里争论换行位置。
- 文件头统一三行：

  ```swift
  // Foo.swift
  // Quick — 原生 macOS 效率启动器
  // @author ygw
  ```

- **import 只写真正用到的。** `QuickUI` / `QuickPlatform` 已经 `@_exported import QuickCore`，
  所以 `import QuickUI` 之后不需要再 `import QuickCore`。`unused_import` 规则会抓这个。
- **类型内部用 `// MARK: - <分组名>` 分段**，顺序建议：类型属性 → 存储属性 → 初始化 →
  公开方法 → 内部方法 → 私有方法。
- 公开 API 显式写 `public`；内部实现**不写** `internal`（它是默认值，写了是噪音）。

---

## 6. 错误处理

- **不要 `try!`**（linter 设为 error）。要么 `try?` 显式接受失败，要么 `do/catch` 处理。
- **不要用 `fatalError` 处理可恢复的错误**。它只用于「编程错误，且状态已不可信」，
  例如 switch 穷尽性兜底。
- **`catch` 里不要空着。** 至少记一条日志：`QuickLog.plugin("clipboard").error("...")`。
  静默吞掉错误是排查困难的头号来源。
- **面向用户的失败要有反馈**：`EventBus` 发 `ShowHUDEvent`，或用 `HUDController` 提示，
  不要把错误只丢进日志。
- **异步 API 用 `async throws`，不返回 `Result`**，除非确实需要把错误当值传递。
- 可选值优先 `guard let ... else { return }` 早返回，避免深层嵌套。

---

## 7. SwiftUI 视图规范

- **视图是值类型，不要在里面存可变的长生命周期状态。** 需要跨视图存活的放协调器或 `Store`，
  需要局部的用 `@State`。
- **一个视图文件一个主体。** 超过约 250 行的视图要拆子视图到同目录下的独立文件，
  命名 `<父视图><部分>View`。
- **`body` 保持纯净**：只做布局与拼装，不做计算、IO、状态突变。
- **不要用 `GeometryReader` 做布局**，除非确实需要测量父容器。它会让布局退化为一次性计算。
- **动画时长取自 `DesignTokens.Duration`。** 不要写 `withAnimation(.easeOut(duration: 0.1))`
  里的裸 `0.1`。
- **颜色、间距、字体、圆角、尺寸全部取自 `DesignTokens`。** 视图里出现裸字面量就是缺陷；
  需要新数值时先往 `DesignTokens` 加一个**有名字、有注释**的令牌。
- **优先系统文本样式**（`.body` / `.callout` / `.headline`）而不是 `.system(size:)` 固定字号 ——
  除了设计令牌里明确规定的几个位置（搜索框、图标），它们有刻意的尺寸。
- **`ZStack`/`overlay` 层数不要超过必要。** 每层都是一次独立的渲染 pass。
- AppKit 桥接一律走 `NSViewRepresentable` / `NSHostingView`，并在 `dismantle` 里清理。

---

## 8. 每个功能的日志与可观测性

**所有代码、所有功能都必须在关键路径上有日志**，这是本项目的硬性要求 ——
出问题时应当能只靠日志定位，不需要重现。

- 统一使用 `QuickLog`，**禁止裸 `print`**（见 [logging.md](logging.md)）。
- 每个插件有自己的 category：`QuickLog.plugin(ClipboardPlugin.id)`。
- 必须打日志的位置：插件 `activate()` / `deactivate()`、外部命令或网络请求的发起与结果、
  权限申请、快捷键注册与失败、持久化读写失败、任何 `catch` 分支、状态机的重要迁移。
- 必须打日志的性能敏感点：面板显隐耗时、聚合搜索耗时与命中插件数、应用扫描耗时与条目数。
- **不要打用户隐私内容**：剪贴板正文、笔记正文、AI 对话内容一律不进日志，
  只记长度或类型。日志里不要出现完整路径以外的个人信息。

具体分级、字段与反例见 [logging.md](logging.md)。
