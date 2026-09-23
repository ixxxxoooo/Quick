# 超级面板（Super Panel）

对齐 Fasty 的双态超级面板：在**鼠标处**弹出一块独立浮层，识别选区 / 剪贴板内容给出
即时动作；没有内容时提供工作台（常用工具 + 最近使用 + 剪贴板预览）。

**它不是插件，而是宿主级组件。** 面板不进主面板搜索、不进插件列表，设置自成一处。
实现挂在 `Quick/SuperPanel/`（窗口与接线）与
`Packages/QuickUI/Sources/QuickUI/SuperPanel/`（模型、动作、视图、设置页）。

- 组件：`SuperPanelController`（`AppCore` 持有）
- 设置页：宿主级「超级面板」分栏
- 快捷键：默认 `⌥C`（对齐 Fasty `Option+C`）

---

## 不变量

1. **超级面板不是插件。** 它不在 `AppCore.registerPlugins()` 里实例化，不出现在
   `pluginEntries`，也不出现在「插件」设置分栏。它是 `AppCore` 直接持有的宿主组件，
   与 `PaletteCoordinator` 平级。
2. **没有主面板入口。** 输入 `sp` / `超级面板` 不会打开它；只有鼠标（右键长按 / 中键）
   与全局快捷键能唤出。它在主面板里当子面板是一条被明确否掉的路径。
3. **独立浮窗，在鼠标处弹出。** `SuperPanelPanel` 是无边框、非激活、跨空间的浮窗；
   落点由 `SuperPanelPlacement` 纯函数决定：默认在光标右下 6pt，右侧 / 下方空间不足
   自动翻到左 / 上，并严格夹进屏幕可见区。
4. **高度随内容自适应。** 根视图量出内容自然高度，协调器把窗口高度夹在 120…620 之间；
   高度变化以光标为锚点重定位（向下的面板顶边不动，向上的底边不动）。
5. **失焦与外部点击收起。** 失焦收起带 350ms 保护期，避免刚弹出就被底层窗口抢焦；
   面板外的鼠标按下也收起。
6. **智能预览是纯逻辑。** `SmartPreviewDetector` 不依赖 AppKit，路径存在性通过注入的闭包
   判断，测试可脱离磁盘。
7. **系统能力由宿主注入。** 抓选区（`SelectionCapture`）、合成粘贴（`PasteService`）、
   最近使用解析都由 `AppCore.wireSuperPanel()` 注入；`QuickUI` 不认识 `QuickPlatform`，
   也不认识插件，依赖方向保持单向。
8. **跳转插件走 `EventBus`。** 打开翻译 / JSON / 颜色等工具走 `NavigateEvent`，
   不直接 `import` 其他插件。
9. **鼠标唤出需要辅助功能权限。** 无权限时监听不启动，设置页提示授权。
10. **`Model/` 下不 import AppKit / SwiftUI。** `SmartPreview`、`SmartPreviewDetector`、
    `SuperPanelPlacement`、`SuperPanelPreferences` 都是纯逻辑，可被测试独立编译。

## 打开方式

| 方式 | 说明 |
| --- | --- |
| 全局快捷键 | 默认 `⌥C`，可在「设置 → 超级面板」改或清空 |
| 右键长按 | 按住右键约 450ms（可调 50–1000ms） |
| 中键单击 | 按下鼠标滚轮键，会保留划词选中 |

鼠标唤出前会先尝试用 ⌘C 抓当前选区（`SelectionCapture`）；没有选区时回落到剪贴板。

## 交互（对齐 Fasty）

| 键 | 行为 |
| --- | --- |
| ← / → | 上下文 ↔ 工作台切换（有内容时才可切） |
| ↑ / ↓ | 在上下文动作列表里移动选中 |
| ↵ | 执行选中项 |
| 1–9 | 直接执行第 n 个动作 / 快捷工具 |
| ⌥↵ | 把结果替换回原应用的选区 |
| esc | 收起 |
| ⌘, | 打开超级面板设置 |

- 点击动作：复制类会给一眼 toast 再收起；跳转类会先收起再打开主面板到目标插件。
- 点击工作台卡片：跳转到对应插件。
- 点击剪贴板预览：把内容替换回原处。

## 智能预览类型（上下文）

| 类型 | 示例 | 主要动作 |
| --- | --- | --- |
| 网址 | `https://…` | 打开、复制 |
| 文件路径 | `/Users/…`、`~/…` | Finder、终端、复制路径 |
| 颜色 | `#FF5500` | 复制 HEX、打开颜色工具 |
| 时间戳 | `1700000000` | 复制格式化时间、打开时间戳工具 |
| Base64 | 可解码明文 | 复制解码结果、打开 Base64 工具 |
| URL 编码 | `%E4%BD%A0` | 复制解码结果、打开 URL 工具 |
| 算式 | `1+2*3` | 复制结果 |
| 邮箱 / 电话 / IP | … | 复制 / mailto / 网络工具 |
| JSON | `{…}` | 打开 JSON 格式化 |
| 中英文本 | 短句 | 打开翻译 |

## 工作台

- **常用工具**：默认八宫格（截图、剪贴板、翻译、AI、备忘、计算、监控、JSON），
  可在设置里增删与排序，点卡片跳转到对应插件。
- **最近使用**：宿主从 `UsageHistory` 解析出最近的应用与工具（最多 4 条）。
- **剪贴板预览**：最近一条剪贴板内容，点击替换回原处，右侧可复制。

## 设置

设置页是宿主级「超级面板」分栏，不走插件页。

| 键 | 类型 | 说明 |
| --- | --- | --- |
| `superPanel.mouseLongPressEnabled` | Bool | 长按右键唤出（默认 true） |
| `superPanel.mouseLongPressThresholdMs` | Int | 长按阈值 ms，50…1000（默认 450） |
| `superPanel.middleClickEnabled` | Bool | 中键单击唤出（默认 true） |
| `superPanel.opacity` | Double | 背景不透明度 0.30…1.0（默认 0.85） |
| `superPanel.material` | String | 背景材质：`hud` / `popover` / `solid`（默认 `hud`） |
| `superPanel.showRecents` | Bool | 工作台显示最近使用 |
| `superPanel.showClipboard` | Bool | 工作台显示剪贴板预览 |
| `superPanel.quickTools` | [String] | 常用工具 id 列表 |

> **关于「模糊度」：** macOS 的 `NSVisualEffectView` 不暴露连续的模糊半径，
> 能换的只有材质本身。所以这里给的是**背景材质**三档，而不是一个调了没用的模糊滑块。

快捷键存在宿主热键服务里，命令 id 为 `core.superPanel`（不进主搜索命令目录）。
