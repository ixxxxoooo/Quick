# JSON 格式化（json-formatter）

格式化与压缩 JSON，单栏原地编辑，另有可折叠树视图。

## 不变量

- **单栏原地格式化，不再分输入/输出两栏。** 「格式化」「压缩」「反转义」都把结果写回
  同一个编辑区（`JSONFormatterView.text`），文本只有这一份真相。
- **压缩永远输出单行**，不受缩进设置影响 —— 缩进只作用于「格式化」。
- **解析用 `JSONSerialization`**，所以 JSON5、尾逗号、注释都不支持；无效输入返回
  `Failure.invalidJSON`，界面显示「无效的 JSON」而不是原样回显。
- `Outcome.nodeCount` 与 `byteSize` 都来自同一次解析，不要为了显示再去解析一遍。
- 缩进设置键是 `jsonFormatter.indent`，与设置页 `JSONFormatterFeatureSection` 共用同一个 `@AppStorage` 键。
- **反转义分自动与手动两条路，逻辑都在 `JSONFormatterLogic`。**
  - `unescape(_:)` 手动：整段带引号的字符串字面量按 JSON 字符串解码；裸的转义正文
    补一层引号再解码。**只解一层** —— 盲目递归会把本该保留的转义也吃掉。
  - `autoUnescape(_:)` 自动：只在「当前不是合法 JSON、且反转义后是合法 JSON」时才改写。
    这样既不会动用户正在写的正常 JSON（含 `\n` 的字符串字面量不会被误伤），
    也不会把普通文本当成转义内容。
- **树视图的折叠状态按「路径」存，不按下标。** 路径由对象键 / 数组下标拼成（`$.a[0]`），
  对象键在拼路径时做 JSON 转义。用下标会在键顺序变化时错位。
- **搜索命中时强制展开命中路径**（`JSONTreeLayout.rows`），与 JSON Viewer / JSON Hero 一致；
  不命中的折叠保持不动。
- **树的默认折叠是「只展开根」**（`defaultCollapsed`），顶层几个键一眼可见，其余收成
  `{n}` / `[n]`。这样大文档不会一进来就铺满屏幕。
- **树是拍平成行再渲染的**（`JSONTreeLayout.rows` + `LazyVStack`），不是递归视图 ——
  只渲染可见行，深/大的 JSON 才不会卡。
- **树的键盘导航走面板的插件内搜索**（`PluginSearchQuery.wantsNavigation` + `commandToken`）。
  头部搜索框在主面板与分离窗口里都保留（本插件声明了 `supportsPanelSearch`），默认不聚焦，
  按 ⌘F 才聚焦；聚焦后方向键会被 field editor 吃掉，与主搜索是同一个坑
  （见 [docs/ui.md](../ui.md)）。转接方在 `PalettePanel.sendEvent`（主面板）与
  `DetachedPluginPanel.sendEvent`（分离窗口）各有一份。
  **只有树视图置 `wantsNavigation = true`**：代码视图要保留方向键给光标、回车给换行。

## 内部结构

| 类型 | 职责 |
| --- | --- |
| `Model/JSONFormatterLogic.swift` | 解析 / 美化 / 压缩 / 反转义 / 字节数（Foundation + CoreFoundation） |
| `Model/JSONTree.swift` | `JSONNode` 节点树、`JSONTreeRow` 可见行、`JSONTreeLayout` 折叠与搜索展开 |
| `UI/JSONFormatterView.swift` | 工具栏 + 代码视图 + 树视图 + 状态栏 |
| `UI/JSONTreeView.swift` | 可折叠树渲染与键盘导航 |

`Model/` 是 Foundation/CoreFoundation only（仓库红线），视图只负责把结果写进 `@State`。

## 已知限制

- **布尔与数字都是 `NSNumber`**，靠 `CFGetTypeID` 与 `CFBooleanGetTypeID` 区分；
  数字经 `Double` 往返，`1.50` 会显示成 `1.5`（`JSONSerialization` 的既有行为）。
- **树视图用整行高亮表示命中**，不做子串精确高亮 —— 键或值命中即整行加粗。
