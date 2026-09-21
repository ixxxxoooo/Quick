# UI 与设计系统

本项目的视觉基准是 **Tinycast 的调色板**：面板尺寸、圆角、间距阶梯、颜色 ramp
都与它对齐（`DesignTokens` 就是它的移植）。改动这里的任何数值前，先读本文件。

规范的目标：**看起来像一个 macOS 系统级组件**，而不是一个套壳的应用。
判断标准是「用户不会意识到这是第三方软件」。

---

## 1. 唯一令牌来源：`DesignTokens`

[`Packages/QuickUI/Sources/QuickUI/DesignSystem/DesignTokens.swift`](../Packages/QuickUI/Sources/QuickUI/DesignSystem/DesignTokens.swift)

**硬性规则：视图里不允许出现裸的间距、圆角、尺寸、颜色、字号、动画时长字面量。**

```swift
// ❌ 全是裸字面量
.padding(.horizontal, 12)
.frame(width: 24, height: 24)
.font(.system(size: 16, weight: .medium))
.background(Color.orange)
withAnimation(.easeOut(duration: 0.1)) { ... }

// ✅ 全部走令牌
.padding(.horizontal, DesignTokens.Spacing.xl)
.frame(width: DesignTokens.Size.rowIcon, height: DesignTokens.Size.rowIcon)
.font(DesignTokens.Typography.iconGlyph)
.background(DesignTokens.Colors.warning)
withAnimation(.easeOut(duration: DesignTokens.Duration.hover)) { ... }
```

需要一个新的数值时，**先往 `DesignTokens` 加一个带名字、带注释的令牌**，
再在视图里引用它。不允许「就这一次先写死」。

---

## 2. 面板几何（与设计基准对齐）

**尺寸是从基准截图反推出来的，不是拍脑袋定的。** 基准截图 1650×1046 物理像素，
macOS 截图是 2x，所以逻辑尺寸是 **825×523** —— 两个维度都精确等于基础令牌
（750×475）× 1.1，对应参考实现的「Large」档。

`DesignTokens.panelScale` 是唯一的缩放开关：

- `1.0` = 基础令牌：面板 750×475，圆角 26
- **`1.1` = 当前采用**：面板 825×523，圆角 29

面板与它的浮动兄弟（HUD、对话框）按此缩放；设置窗口这类系统窗口不缩放。
`Size.hairline` **刻意不缩放** —— 它是物理像素级的东西，跟着放大只会变成粗边。

| 令牌 | 基础值 | 当前实际值 |
| --- | --- | --- |
| `Size.panelWidth` | 750 | **825** |
| `Size.panelHeight` | 475 | **523** |
| `Radius.panel` | 26 | **29** |
| `Size.headerHeight` | 44 | 48 |
| `Size.headerIconSlot` | 22 | 24 |
| `Size.headerPadding` | 10 | 11 |
| `Size.bottomBarHeight` | 52 | 57 |
| `Size.barButtonHeight` | 28 | 31 |
| `Size.rowIcon` | 24 | 26 |
| `Size.keyCap` / `compactKeyCap` | 18 / 15 | 20 / 17 |
| `Size.edgeFadeHeight` | 22 | 24 |
| `Radius.row` / `barControl` / `keyCap` | 10 / 8 / 6 | 11 / 9 / 7 |
| `Typography.searchFieldSize` | 20 | 22 |

`Radius.panel` 是「系统组件感」的主要来源，不要随意调小。

### 面板结构：内容从浮动栏下面穿过

```
┌────────────────────────────────────────────────┐
│  [icon] 搜索框                          [状态]  │  header（无背景、无分隔线）
│                                                  │
│   结果行从 header 下面穿过并淡出                  │
│                                                  │
│  计数                              ( 打开  ↵ )   │  浮动胶囊，无通栏
└────────────────────────────────────────────────┘
```

- **没有分隔线。** 搜索框下面没有、底栏上面也没有。栏位与内容之间靠**渐隐**分界，
  不是靠线。
- **没有通栏底栏。** 底栏只有两个浮动的元素：左侧状态文本、右侧一枚玻璃胶囊
  （`View.frosted(in: Capsule())`）。它没有背景色，行的内容从它下面穿过。
- **栏位用 `safeAreaInset` 挂在滚动内容上，不是兄弟节点。** 兄弟节点会把滚动区
  **硬切**在栏位边缘，滚动时能看到行被齐刷刷切断。`safeAreaInset` 让内容从栏位下面
  穿过去：静止时贴边、滚动时渐隐。这是参考实现的做法，也是「看起来像一个系统组件」
  而不是「一个被裁掉一块的列表」的关键。
- **不要给 header 加背景。** 加了就变成通栏，穿过与渐隐的层次感会消失。
- 列表必须挂 `edgeDissolve()`；它由滚动几何驱动，**贴边时完全不淡**
  （否则第一行会莫名变浅），滚出越多越淡。实现见
  `DesignSystem/Scrolling/EdgeDissolve.swift`，注意其中的渐变断点必须包含
  **带外的两个全不透明点**，少了它们会把整片列表冲淡。
- **隐藏系统滚动条**（`.scrollIndicators(.never)`）：它是为带标题栏的窗口设计的，
  和面板的玻璃语言冲突。面板高度固定、条目数有限，滚动位置靠键盘导航足够可感。

### 列表行：单行 + 右侧类型标签

```
[icon 26]  标题 ······················  类型标签 / 键位提示
```

- 行高由内容 + `Spacing.md` 上下内边距决定，不写死。
- **副标题放在右侧，不放标题下方。** 放标题下方会把行高翻倍，一屏能看到的条目少一半。
- 选中/悬停用 `Colors.selection` / `Colors.rowHover` 填充，悬停更淡，
  两者视觉上必须可区分。

### 尚未对齐基准的两处（有意为之，不是漏掉）

| 基准有 | 我们没有 | 原因 |
| --- | --- | --- |
| 分组标题（`Applications`） | 无 | 我们的结果按**跨插件相关度**全局排序；按插件分组会打断这个排序，而启动器的主路径是「打几个字就打开」，全局排序更重要 |
| 左下角的圆形菜单钮 | 无 | 面板内还没有「应用菜单」这件事可开。放一个点了没反应的按钮比不放更糟；等有了真实菜单项再加 |

---

## 2b. 设置窗口

设置窗口是**普通窗口**，不是面板：有标题栏、可关闭、跟随系统的窗口语言。
面板那套（无边框、非激活、跨空间）在这里全都不适用。

结构与参考实现的设置页一致：**侧边栏 + 详情**两栏。

```
┌──────────────┬──────────────────────────────────┐
│ 🔍 搜索设置   │  启动                             │
│              │  ┌────────────────────────────┐  │
│ 设置          │  │ ⏻ 开机自动启动        [开关] │  │
│ ⚙ 通用        │  │   登录后在菜单栏常驻…        │  │
│ ▦ 插件        │  └────────────────────────────┘  │
│ 🛡 权限        │  唤出                             │
│ ⓘ 关于        │  ┌────────────────────────────┐  │
│              │  │ ⌨ 全局快捷键         [⌥Space]│  │
└──────────────┴──────────────────────────────────┘
```

- **侧边栏**：`List(selection:)` + `.listStyle(.sidebar)`，顶上一个搜索框。
  输入后切换成搜索结果，在结果里上下移动就把详情切过去。
- **详情**：`.formStyle(.grouped)` 的分组卡片，每行是 `SettingsRow`
  （**固定宽度的图标槽位 + 标题/副标题 + 弹性空隙 + 尾部控件**）。
- **副标题不是装饰。** 一个只有「开机自动启动」的开关说不清它会做什么，
  一行灰字才能。权限页尤其如此：只要求授权不说用途，用户没有判断依据。
- **置灰要同时降不透明度**（`settingsEnabled(_:)`）：只用 `.disabled`
  会让标题保持全黑，看起来像能点。
- 设置搜索是**手写清单**（`SettingsSearchCatalog`），不自动扫描视图树 ——
  SwiftUI 的视图树扫不出来，而清单只有几十行。这是有意的取舍。

### 面板里的键盘导航（为什么不在 SwiftUI 层）

上下键与回车**在 `PalettePanel.sendEvent` 里拦截**，不在 SwiftUI 视图上。

原因：面板打开时焦点在搜索框里，field editor 会先把上下键拿去移动光标、
把回车当成提交；挂在结果列表上的 `onKeyPress` 收不到事件 —— 列表既不是焦点，
也不是输入框的祖先。这个坑已经踩过一次（列表完全无法用键盘操作）。

拦到的按键写进 `PaletteSelection`（一个**不持有窗口**的 `@Observable` 对象，
所以被 SwiftUI 观察是安全的；会与 AttributeGraph 死循环的是协调器本身）。



---

## 3. 间距阶梯

**只用这七档，不要发明中间值**（2 / 4 / 6 / 8 / 10 / 12 / 20）：

| 令牌 | 值 | 典型用途 |
| --- | --- | --- |
| `Spacing.xxs` | 2 | 列表行之间的间隙、标题与副标题之间 |
| `Spacing.xs` | 4 | 行内紧密元素 |
| `Spacing.sm` | 6 | 图标与文字的小间隔 |
| `Spacing.md` | 8 | 列表容器内边距、行内主间隔 |
| `Spacing.lg` | 10 | 行内水平内边距 |
| `Spacing.xl` | 12 | 面板水平内边距 |
| `Spacing.xxl` | 20 | HUD 水平内边距 |

其余专用令牌：`sectionHeaderBottom`(4)、`sectionSpacing`(12)。

---

## 4. 颜色：靠 ramp，不靠硬编码

颜色分两种写法，选错会导致明暗模式切换时出问题：

```swift
// ramp：深色用白墨、浅色用黑墨。用于所有「文本/前景/叠加层」
static func ramp(dark: Double, light: Double) -> Color

// adaptive：两个模式各给一个具体颜色。用于「有色彩倾向」的颜色
static func adaptive(dark: NSColor, light: NSColor) -> Color
```

| 令牌 | ramp（dark / light） | 用途 |
| --- | --- | --- |
| `Colors.textPrimary` | 1.0 / 1.0 | 主文本、行标题 |
| `Colors.textSecondary` | 0.60 / 0.60 | 副标题 |
| `Colors.textTertiary` | 0.40 / 0.42 | 快捷键提示、占位符 |
| `Colors.selection` | 0.10 / 0.09 | 选中行填充 |
| `Colors.rowHover` | 0.05 / 0.045 | 悬停行填充（比选中更淡） |
| `Colors.separator` | 0.10 / 0.12 | 分隔线、hairline |
| `Colors.controlSurface` | 0.10 / 0.08 | 快捷键帽、小控件底 |
| `Colors.border` | 0.20 / 0.18 | 控件描边 |
| `Colors.cardFill` / `cardStroke` | 0.05 / 0.10 | 卡片 |

语义色：`destructive`(红)、`success`(绿)、`progress`(蓝)、`warning`(橙)。
**不要直接写 `Color.orange` 之类**，用语义令牌 —— 这样将来统一调整只改一处。

### 深色是基准

深色模式的表现是设计基准（macOS 用户大量使用深色）。新加颜色时：

- 深色分支的值是**刻意定的**，不要「顺手调一下」—— 那是视觉回归。
- 浅色分支可以自由调整。
- 两个模式都要亲眼确认，不能只改一个就提交。

### 玻璃与材质

- 面板背景走 `PaletteBackground`：原生 vibrancy（`NSVisualEffectView`，材质 `.hudWindow`、
  混合模式 `.behindWindow`）+ `Colors.panelScrim` 压暗 + 极淡的边缘高光。
  用 `NSVisualEffectView` 而不是 SwiftUI 的 `.ultraThinMaterial`，是因为材质、混合模式与
  强调状态都需要显式指定才能和系统其他面板一致。
- 边缘高光的线宽用 `Size.hairline / displayScale` —— 直接用 `hairline` 在 2x 屏上会是 2px 的粗边。
- 需要「浮起的玻璃控件」时用现成的 `View.frosted(in:)` 修饰器，它封装了
  `.glassEffect(.regular.interactive().tint(...))`。**不要在视图里重复写这段配置。**
- 不要堆叠多层玻璃 —— 每层都是一次独立的 GPU pass，且会互相糊掉。

### 投影由 AppKit 负责，不要在 SwiftUI 里画

**面板与 HUD 的投影来自窗口阴影（`NSPanel.hasShadow`），`DesignTokens` 里没有阴影令牌。**

原因：窗口阴影绘制在窗口**之外**，形状直接取自窗口的 alpha 通道，所以圆角就是圆角。
如果改成 SwiftUI 的 `.shadow`，阴影会被窗口边界裁切，在圆角外侧的方形三角区留下
不透明的暗块 —— 看起来就是「圆角外面多了一层方角」；而且它会把窗口 alpha 撑成方形，
连带把 AppKit 的窗口阴影也变成方角。

判断方法：若某处需要投影，先问「这是一个窗口吗」。是 → 用 `hasShadow`；
不是（例如自绘的卡片）→ 才考虑自绘阴影，并且要确保阴影有足够的绘制空间不被裁切。

---

## 5. 字体

| 令牌 | 值 | 用途 |
| --- | --- | --- |
| `Typography.searchField` | 20pt regular | 搜索输入框 |
| `Typography.headerIcon` | 18pt medium | 搜索栏图标 |
| `Typography.rowTitle` | `.body` | 列表行标题 |
| `Typography.rowTrailing` | `.callout` | 列表行副标题、右侧文本 |
| `Typography.sectionHeader` | `.subheadline` medium | 分组标题 |
| `Typography.panelTitle` | `.headline` | 面板标题 |
| `Typography.bar` | `.callout` medium | 底栏按钮文字 |
| `Typography.keyCap` | `.caption` | 快捷键帽 |
| `Typography.code` | `.callout` 等宽 | 代码 |
| `Typography.inlineCode` | `.body` 等宽 | 行内代码 |

- **优先系统文本样式**（`.body` / `.callout` / `.headline`），它们会跟随
  Dynamic Type 与无障碍设置。固定字号只用于设计令牌明确规定的两处：搜索框与图标。
- **不要用 `.system(size:)` 在视图里现造字号**。图标尺寸不够用就往令牌里加。
- 字重克制：`regular` / `medium` / `semibold` 足够。不要 `heavy` / `black`。

### 图标尺寸只有四个角色

图标全部来自 **SF Symbols**（`Image(systemName:)`；AppKit 侧是
`NSImage(systemSymbolName:)`）。仓库没有、也不该有第三方图标库。

| 角色 | 令牌 | 用在哪 |
| --- | --- | --- |
| 行图标 | `Typography.iconGlyph`（16pt medium）+ `Size.rowIcon` 槽位 | 列表行的**前导**图标，与标题成列 |
| 侧边栏图标 | `Typography.sidebarIcon`（13pt regular）+ `Size.sidebarIconSlot` | 设置窗口侧边栏；跟着侧边栏文字走，比行图标小一档 |
| 行内图标 | `Typography.inlineIcon`（13pt regular） | 与正文同排的图标：搜索框放大镜、清除按钮、警告三角、复制按钮 |
| 小控件图标 | `Typography.compactIcon`（11pt regular） | 别名框、快捷键录制器里的清除按钮 |

两条纪律：

- **每个图标都要显式指定字号，一个都不许省。** 不给 `.font` 的图标会继承容器字号，
  于是同一个面板里出现「有的 16、有的 13」—— 这正是这一组令牌要消掉的问题，
  而它曾经真的发生在设置页里（12 个图标在静默继承）。
- **槽位宽度也要统一。** 图标尺寸一致但槽位宽度不一致，标题的起始位置照样逐行漂移。
  行图标统一 24，侧边栏统一 18。
- 图标是**语义**不是装饰：选 SF Symbol 时挑表意准确的那个，不要为了好看换。

---

## 6. 动画

| 令牌 | 值 | 用途 |
| --- | --- | --- |
| `Duration.enter` | 0.18 | 面板进入 |
| `Duration.exit` | 0.12 | 面板退出（比进入短，体感才「快」） |
| `Duration.hover` | 0.12 | 悬停高亮 |
| `Duration.tooltip` | 0.15 | 提示淡入淡出 |
| `Duration.copyFeedback` | 1.2 | 复制反馈停留 |
| `Duration.messageHUD` | 2.4 | HUD 停留 |

- **退出永远比进入快。** 用户按下 Esc 时希望立刻消失，不希望看动画。
- **动画时长的用途要对**：0.1 秒用于滚动定位，0.18 用于面板出现，不要混用。
- 面板的窗口动画用 `panel.animationBehavior = .none` + 自己做 alpha 渐入 ——
  系统默认的窗口动画在无边框面板上会产生边框闪烁。
- 尊重「减少动态效果」无障碍设置：装饰性动画应检查
  `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`。

---

## 7. 组件清单

`Packages/QuickUI/Sources/QuickUI/` 下的共享组件。

### DesignSystem/

| 组件 | 职责 |
| --- | --- |
| `DesignTokens` | 全部设计令牌 + `panelScale` 缩放，以及 `NSColor.srgbInk` / `NSAppearance.isDark` / `View.frosted(in:)` |
| `VisualEffectView` | 原生 vibrancy 背景（`NSVisualEffectView` 的 SwiftUI 封装） |
| `PaletteBackground` | 面板背景：vibrancy + scrim + 边缘高光，一处配置。**不含投影** |
| `Scrolling/EdgeDissolve` | 滚动内容在浮动栏下方淡出的遮罩，`.edgeDissolve()` 挂载 |
| `KeyCapChip` | 快捷键帽。`.filled`（底栏）/ `.outline`（列表行）两种样式 |
| `BarButton` | 底栏按钮：悬停胶囊 + 图标/文字 |
| `SectionHeader` | 列表分组标题（当前未使用：我们不做分组，见 §2） |

### Components/

| 组件 | 职责 |
| --- | --- |
| `SearchFieldView` | 统一搜索输入框（图标固定槽位 + 20pt 输入） |
| `ResultListView` | 统一结果列表（键盘导航 + 悬停 + 滚动跟随）。`ResultRowView` 是它的行 |

### Panel/

| 组件 | 职责 |
| --- | --- |
| `PalettePanel` | 无边框非激活 `NSPanel`，拦截 Esc / 裸退格 / ⌘D / ⌘ 快捷键 |
| `PaletteCoordinator` | 面板生命周期、定位、聚合搜索。**不要加 `@Observable`** |
| `PaletteMode` | 面板模式状态桥接（`@Observable`）：搜索模式 vs 插件模式。不持有 NSPanel，安全观察 |
| `PaletteRootView` | 面板外壳：搜索模式（header / content / bottom bar 三段）或插件模式（插件头部 + makeView） |
| `PluginHeaderView` | 插件模式头部：返回按钮 + 插件图标/名称 + 分离按钮（⌘D） |

### Windows/

| 组件 | 职责 |
| --- | --- |
| `HUDController` | 屏幕底部轻量提示，`show(message:tone:duration:)` |
| `PluginPanelController` | 分离窗口管理：创建独立 NSWindow、单例策略、尺寸记忆、关闭 |

---

## 8. 组件复用纪律

- **面板内的一切都复用 `QuickUI` 的组件。** 插件的 `makeView()` 返回内容**放进**
  面板外壳里，不要自己造一套搜索栏或列表 —— 那会立刻产生视觉不一致。
- **插件自己的视图只管内容区**，不要设外层尺寸、圆角、背景（外壳负责）。
- **不要复制粘贴组件。** 需要变体就给现有组件加一个参数或样式枚举
  （参考 `KeyCapChip.Style`）。
- 新的共享组件必须：从令牌取所有数值、支持明暗两模式、在 `docs/ui.md` 登记。

---

## 9. 对话框与提示

- **不要用 `NSAlert`。** 系统弹窗和面板的视觉语言完全冲突（面板是无边框玻璃，
  `NSAlert` 是标题栏窗口）。需要确认时用应用内的自定义对话框面板，
  复用 `Radius.dialog`(20) + `Size.dialogWidth`(420) + 材质背景。
- **轻量反馈走 `HUDController`**（底部胶囊提示），用 `HUDTone` 表达语义：
  `.success` / `.info` / `.warning` / `.danger`。
- 需要提示或错误文案时，文案规则：**说清发生了什么 + 下一步能做什么**，
  不要「操作失败」这种没有信息量的话。
- 空状态必须有：一个图标 + 一句说明（参考 `PaletteRootView.emptyState`），
  不要留一片空白。

---

## 10. 无障碍

- 所有纯图标按钮必须有 `.accessibilityLabel`。图标本身不传达意义。
- 交互元素的点击区域不小于 28×28（`Size.barButtonHeight` 是下限）。
- 不要只靠颜色传达状态：选中态除了填充色，还应有其他可感知的差异
  （位置、图标、字重）。
- 文本对比度：`textTertiary` 是允许的最淡文本，不要再用更淡的颜色做正文。
- 键盘可达：面板内所有主要操作都要能用键盘完成，这也是底栏要展示快捷键的原因。

---

## 11. 设置页的控件必须真的生效

**一个能拨动却什么也不做的开关比没有这个开关更糟**：用户会以为功能坏了，而且他会先怀疑
自己没设置对。这类缺陷在本仓库真实发生过，而且一次就有一大批 —— 46 个偏好键里有 39 个
只有设置页在写、代码里没有任何地方读。

规则：

- 每个设置键都必须有一个**读取方**，而且要在**动作发生的那一刻**读，不是在 `init` 里缓存一次 ——
  设置页可以在应用运行期间改它。
- 默认开启的开关，读取时必须把「键不存在」和「显式关掉」区分开：
  `bool(forKey:)` 会把「没设置过」读成 `false`，等于默认关闭。用
  `object(forKey:) != nil` 先判断。
- 功能还没实现的控件：**禁用并标注**（`PendingFeatureNote`），不要让它看起来能用。
  保留控件是为了让路线图可见，但那必须写在界面上。
- 控件对应的功能如果根本不存在（不是「没接上」而是「没做」），把控件和键一起删掉 ——
  等做出来再加回来。留着一个无引用的键，下一个人只会以为它是活的。
- 设置页要展示的插件元信息（有哪些命令、叫什么、什么图标）由**插件提供**、经
  `SettingsDataSource` 桥接，不要在设置页里再抄一份。抄一份的下场是 id 漂移：
  曾经有 4 个布局命令的开关写进了插件永远不读的键里，因为设置页按枚举 case 名写键、
  而插件按 rawValue 读键。
- 键集中登记在 `PluginSettingKey`。设置页与读取方引用同一个常量，拼错就是编译错误。
