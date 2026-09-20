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

## 2. 面板几何（与 Tinycast 对齐）

这些数值是刻意的，改动前必须确认视觉无回归：

| 令牌 | 值 | 说明 |
| --- | --- | --- |
| `Size.panelWidth` | **750** | 面板宽度，与 Tinycast 一致 |
| `Size.panelHeight` | **475** | 面板高度，与 Tinycast 一致 |
| `Radius.panel` | **26** | 面板圆角。**这个值不能随意调小**，它是「系统组件感」的主要来源 |
| `Size.headerHeight` | 44 | 搜索栏高度 |
| `Size.headerIconSlot` | 22 | 搜索图标固定槽位宽（保证不同模式下输入起点在同一 x） |
| `Size.headerPadding` | 10 | 搜索栏上方留白，恒定 —— 输入时栏位不能跳动 |
| `Size.bottomBarHeight` | 52 | 底栏高度 |
| `Size.barButtonHeight` | 28 | 底栏按钮 / 快捷键胶囊高度 |
| `Size.rowIcon` | 24 | 列表行图标 |
| `Size.keyCap` | 18 | 快捷键帽边长 |
| `Size.paletteTopMarginFraction` | 0.18 | 面板顶边距屏幕可见区顶部的比例 |
| `Radius.row` | 10 | 列表行圆角 |
| `Radius.keyCap` | 6 | 快捷键帽圆角 |
| `Radius.barControl` | 8 | 底栏控件圆角 |

### 面板的三段式结构

```
┌──────────────────────────────────────────────────────────────┐
│  [icon 22]  搜索框 20pt                              [模式徽章] │  header 44
│  ──────────────────────────────────────────────────────────  │  hairline
│                                                              │
│   结果行 ×N（icon 24 · 标题 .body · 副标题 .callout）           │  content（弹性）
│   选中行：Radius.row 圆角填充 Colors.selection                  │
│                                                              │
│  ──────────────────────────────────────────────────────────  │  hairline
│  [⌘K 次要动作]              [↑↓ 选择] [↵ 打开] [esc 关闭]        │  bottom bar 52
└──────────────────────────────────────────────────────────────┘
```

- **header 高度恒定**，搜索栏不因输入内容变化而位移（`headerPadding` 恒定就是为此）。
- **底栏是快捷键的教学位**：左侧是当前上下文的主动作，右侧是全局导航键。
  底栏文案用 `Typography.bar`，键位用 `KeyCapChip`。
- **列表行高度**由内容 + `Spacing.md` 上下内边距决定，不写死；选中/悬停态用
  `Colors.selection` / `Colors.rowHover` 填充，两者视觉上要可区分（悬停更淡）。

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
| `DesignTokens` | 全部设计令牌，以及 `NSColor.srgbInk` / `NSAppearance.isDark` / `View.frosted(in:)` |
| `VisualEffectView` | 原生 vibrancy 背景（`NSVisualEffectView` 的 SwiftUI 封装） |
| `PaletteBackground` | 面板背景：vibrancy + scrim + 边缘高光，一处配置。**不含投影** |
| `KeyCapChip` | 快捷键帽。`.filled`（底栏）/ `.outline`（列表行）两种样式 |
| `BarButton` | 底栏按钮：悬停胶囊 + 图标/文字 |
| `SectionHeader` | 列表分组标题 |

### Components/

| 组件 | 职责 |
| --- | --- |
| `SearchFieldView` | 统一搜索输入框（图标固定槽位 + 20pt 输入） |
| `ResultListView` | 统一结果列表（键盘导航 + 悬停 + 滚动跟随）。`ResultRowView` 是它的行 |

### Panel/

| 组件 | 职责 |
| --- | --- |
| `PalettePanel` | 无边框非激活 `NSPanel`，拦截 Esc / 裸退格 / ⌘ 快捷键 |
| `PaletteCoordinator` | 面板生命周期、定位、聚合搜索。**不要加 `@Observable`** |
| `PaletteRootView` | 面板外壳：header / content / bottom bar 三段 |

### Windows/

| 组件 | 职责 |
| --- | --- |
| `HUDController` | 屏幕底部轻量提示，`show(message:tone:duration:)` |

---

## 8. 组件复用纪律

- **面板内的一切都复用 `QuickUI` 的组件。** 模块的 `makeView()` 返回内容**放进**
  面板外壳里，不要自己造一套搜索栏或列表 —— 那会立刻产生视觉不一致。
- **模块自己的视图只管内容区**，不要设外层尺寸、圆角、背景（外壳负责）。
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
