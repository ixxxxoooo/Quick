# 剪贴板历史（clipboard）

监听系统剪贴板变化，记录文本历史，支持搜索与收藏。

## 不变量

- **相同内容的条目不会重复记录（`clipboard.deduplication` 打开时，默认打开）。**
  `add(_:)` 先 `removeAll` 掉同 `text` 的旧条目再插入新的，所以「复制同一段文字两次」
  在历史里只有一条，且 `id` 与时间戳是**后一次**的。这依赖 `text` 完全相等 ——
  不要把比较改成 `preview` 或前缀比较，那会把两段前缀相同的内容误判为重复。
  关掉这个开关时不发去重语句，两条都留下（顺序仍是新的在前）。
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
| `ClipboardPlugin` | 插件入口，把 `ClipboardMonitor` 的新内容转给 `ClipboardStore` |
| `ClipboardMonitor` | 轮询系统剪贴板，回调 `onNewContent` |
| `ClipboardStore` | 内存缓存 + 去重 + 上限裁剪 + 防抖落盘 |
| `ClipboardEntry` | 值类型条目（`Codable` + `Sendable`） |
| `ClipboardListView` | 插件主视图 |
| `ClipboardListNavigation` | 上下键移动下标的纯函数（两端夹取、下标越界时也要能走） |
| `ClipboardSettingsView` | 设置页 |

`ClipboardStore` 标了 `@Observable`，供 `ClipboardListView` 观察。
**注意这不违反「不要给持有 NSPanel 的对象加 `@Observable`」** —— 那条规则针对的是
`PaletteCoordinator`。Store 是被视图观察的数据源，用 Observation 是正确做法。

## 持久化

`clipboard_history` 表，在应用唯一的 `quick.db` 里（迁移 id `clipboard.history`）。
图片以 PNG 存在 `image_data` 列（BLOB），不落成散文件。

- **`init(storage:)` 接收存储句柄，并在 `init` 里同步加载。** 测试传内存库
  （`SQLiteDatabase()` + 跑一遍 `ClipboardPlugin.storageMigrations`），既不碰磁盘，
  也不会污染用户真实历史。
- **改动直接落库，没有防抖。** 以前整份历史是一个 JSON 文件，写一次就是重写全文，
  所以必须攒批 2 秒；现在每条记录一行，`add` 的代价与历史长度无关，防抖只会让
  「复制完立刻崩溃」丢掉刚复制的内容。
- **一次 `add` 是一个事务，语句顺序不能换**：先删重复、再插入、最后按上限剪枝。
  反过来的话，去重那一步会把刚插入的这条自己删掉，而且不报错。
- **数据库是唯一真相。** 置顶会改变排序，而排序由 SQL 的 `ORDER BY` 定义，
  所以任何写操作结束后都从库里重读内存缓存，不在内存里推算「应该剩哪些」。
- 单行坏数据只丢那一行（`entry(from:)` 返回 nil 就跳过），不像 JSON 那样整份历史归零。

### 两条上限

| 上限 | 设置键 | 默认 | 豁免 |
| --- | --- | --- | --- |
| 条数 | `clipboard.maxEntries` | 500 | 置顶、收藏 |
| 图片总字节 | `clipboard.imageByteBudget` | 256 MB | 置顶、收藏 |

条数上限以前硬编码在 store 里，设置页那个 Stepper 改了没有任何效果 —— 现在两边读同一个键。
图片预算用一条带窗口函数的 SQL 算「从最新往回累加，累到超预算为止」，超出的部分即剪枝对象。

### 四个开关

开关都在**用到的那一刻**读 `UserDefaults`，不缓存：设置页可以在运行期改，缓存下来的值
迟早和真实设置漂移，表现就是「改了没反应」。读取统一走 `PluginDefaults.isEnabled(_:default:)`
—— 它把「用户没动过」和「用户关掉了」区分开（`bool(forKey:)` 直读会把前者读成 `false`）。

| 开关 | 键 | 默认 | 读的地方 |
| --- | --- | --- | --- |
| 启用剪贴板监听 | `clipboard.monitorEnabled` | 开 | `ClipboardPlugin.applyMonitorSetting()` |
| 退出时清除历史 | `clipboard.clearOnQuit` | 关 | `ClipboardPlugin.deactivate()` |
| 显示内容预览 | `clipboard.showPreview` | 开 | `ClipboardPlugin.searchItems(query:)` |
| 自动去重 | `clipboard.deduplication` | 开 | `ClipboardStore.add(_:)` |

「启用剪贴板监听」是唯一一个**必须即时生效**的：关掉之后还在记录剪贴板等于骗用户。
它在 `activate()` 与 `deactivate()` 之外还观察 `UserDefaults.didChangeNotification`，
所以 `ClipboardMonitor.start()` 必须是幂等的 —— 每次设置写入都会触发一次重新判定。
「显示内容预览」关掉时结果仍在，只是标题退化成内容类型、副标题带上类型名，
**标题与副标题都不许出现剪贴板正文**。

## 已知限制

- **单条图片上限 5MB**（`ClipboardMonitor` 里的限制），超过就整条丢弃 ——
  大图进库会拖慢每次读取。
- **只处理文本与图片。** 类型推断（`ClipboardMonitor.detectContentType`）把文本分成
  `.url` / `.color` / `.code` / `.text`；文件、富文本一律被忽略。
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
