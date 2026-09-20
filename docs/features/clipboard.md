# 剪贴板历史（clipboard）

监听系统剪贴板变化，记录文本历史，支持搜索与收藏。

## 不变量

- **相同内容的条目不会重复记录。** `add(_:)` 先 `removeAll` 掉同 `text` 的旧条目再插入
  新的，所以「复制同一段文字两次」在历史里只有一条，且 `id` 与时间戳是**后一次**的。
  这依赖 `text` 完全相等 —— 不要把比较改成 `preview` 或前缀比较，
  那会把两段前缀相同的内容误判为重复。
- **历史上限 500 条，且裁剪时保留置顶与收藏。** 裁剪逻辑是
  「所有 pinned/favorite + 未被标记的前 500 条」，所以**收藏条目不计入上限**，
  理论上总数可以超过 500。这是刻意的：不能因为历史满了就把用户主动收藏的东西删掉。
- **`clearHistory()` 保留收藏与置顶。** 它是「清空历史」不是「清空数据」，
  用户点它时不期望连收藏一起没。
- **搜索是 `contains` 子串匹配 + 小写化，不是模糊匹配。** 空查询返回全部。
  剪贴板内容是长文本，模糊匹配会返回大量无意义的命中。
- **`preview` 必须把三种换行都压平。** 从 Windows / 网页复制来的文本常带 `\r\n`；
  只替换 `\n` 会留下游离的 `\r`，在列表里显示成断行。这也是 `\t` 被转成空格的原因。
- **`preview` 截断到 80 字符并追加 `…`**，所以最长是 81 个字符。
  列表行靠 `lineLimit(1)` 兜底，但截断本身必须在这里做 —— 列表不该为长文本付布局代价。
- **落盘是防抖 2 秒的，不是即时的。** 剪贴板可能连续变化多次，每次都写盘既浪费又会
  互相打断。所以**进程被强杀时最后 2 秒的内容会丢**，这是接受的代价。
  `deactivate()` 里的 `save()` 是唯一的即时落盘点。

## 内部结构

| 类型 | 职责 |
| --- | --- |
| `ClipboardModule` | 模块入口，把 `ClipboardMonitor` 的新内容转给 `ClipboardStore` |
| `ClipboardMonitor` | 轮询系统剪贴板，回调 `onNewContent` |
| `ClipboardStore` | 内存缓存 + 去重 + 上限裁剪 + 防抖落盘 |
| `ClipboardEntry` | 值类型条目（`Codable` + `Sendable`） |
| `ClipboardListView` | 模块主视图 |
| `ClipboardSettingsView` | 设置页 |

`ClipboardStore` 标了 `@Observable`，供 `ClipboardListView` 观察。
**注意这不违反「不要给持有 NSPanel 的对象加 `@Observable`」** —— 那条规则针对的是
`PaletteCoordinator`。Store 是被视图观察的数据源，用 Observation 是正确做法。

## 持久化

`history.json`（`ClipboardEntry` 的 JSON 数组），路径走 `AppPaths.moduleData("clipboard")`。

- `init(storageURL:)` 接收可选路径，默认走 `AppPaths`。
  **测试必须传临时目录**，否则会污染用户真实的剪贴板历史。
- 解码失败降级为空历史并记 `.error`，不让模块起不来。

## 已知限制

- **只记录文本。** 类型推断（`ClipboardMonitor.detectContentType`）会把内容分成
  `.url` / `.color` / `.code` / `.text`，但**只处理文本类型**：图片、文件、富文本
  一律被忽略，`pasteboard.string(forType: .string)` 取不到就丢弃。
- **类型推断是启发式的，会误判。** 判定顺序是 URL → 颜色 → 代码 → 文本：
  - `URL(string:)` 只要有 scheme 就算 URL，所以 `a:b` 这类字符串会被误判为 URL。
  - 颜色只认 `#RGB` 与 `#RRGGBB` 两种形式，`rgb(...)` / 具名颜色都不认
    （注释里提到过 `rgb(...)`，但代码没有实现）。
  - 代码判定要求**同时**含代码特征词（`{`、`func `、`let ` 等）**和换行**，
    所以单行代码片段会被归为 `.text`。
  - 不要为了「更准」随意调整这个顺序 —— 先改的规则会吃掉后面的所有情况。
- **不忽略密码管理器标记的机密内容。** 某些密码管理器会在剪贴板里标记条目为机密，
  当前实现不做区分。
- **不加密落盘。** 剪贴板历史以明文 JSON 存在 Application Support 下，
  所以剪贴板里出现过的密码会留在磁盘上。这是已知的安全权衡，改动前需要明确讨论。
- **轮询而非监听。** macOS 没有剪贴板变化通知，只能轮询（当前 500 ms）。
  所以「复制后立刻在历史里看到」最多有半秒延迟，这是设计而非缺陷。
