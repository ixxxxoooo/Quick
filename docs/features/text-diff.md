# 文本对比（text-diff）

左右两个**可编辑的代码编辑器**：打字即上色，逐行标红 / 绿底，左右按行号对齐。

## 不变量

- **是按行位置对齐，不是 LCS 最长公共子序列**：中间插入一行会让其后所有行都被标成「删一行 + 加一行」。改算法等于改可见行为，需同步改测试。
- **空串等价于一行空行**：`diff("", "")` 会给出 1 行 `.same`（空行）而不是 0 行；`diff("", "x")` 是 1 删 1 加。
- `DiffLine.LineType` 嵌在 `DiffLine` 里，视图按原拼写使用它。
- **对比长在编辑器里，不是另起一段结果列表。** 左右各一个 `CodeEditorView`（AppKit 原生 `NSTextView`）：可编辑、语法高亮、行号槽、逐行红绿底。旧实现把差异单独铺在输入框下面，用户明确否掉了 —— 那样看不出「哪一行变成了哪一行」。
- **按行号对齐靠三件事，缺一不可**：关闭软换行（长行横向滚动）、两个编辑器共用同一条固定行高（`Size.codeEditorLineHeight`）、垂直滚动同步（`EditorScrollSync`）。任何一条被改掉，左右就会错位。
- **逐行状态由 `TextDiffLogic.sideLineStates` 给出**，分别对应两侧行号：内容相同 → 两侧不标；同一行两边不同 → 原文标删、修改后标增；一侧没有这一行 → 只给有内容的那侧标。视图不自己配对一维流。
- **上色只改属性、不换字符**：`TextDiffView` 的编辑器在 `textDidChange` 里对 `NSTextStorage` 做 `setAttributes` + `addAttribute`，保留选区与输入法合成，绝不用 `setAttributedString` 重建整段文本。
- **底色范围包含行尾换行**，让底色至少延续到该行文字末尾（关闭软换行后不会铺满整个视口宽度，这是接受的取舍）。
- **语法高亮语言可切换**（`CodeLanguage`：纯文本 / JSON / SQL）。对比任意文本默认纯文本，不假装能识别语言。

## 内部结构

| 类型 | 职责 |
| --- | --- |
| `Model/TextDiffLogic.swift` | 纯逻辑（Foundation only）：`diff` 一维流、`sideLineStates` 逐行状态、`render` 可复制文本 |
| `UI/TextDiffView.swift` | 工具栏 + 左右编辑器 + 滚动同步接线 |
| `QuickUI/Syntax/CodeEditorView.swift` | 可编辑的语法高亮编辑器（`NSTextView` + 行号槽） |
| `QuickUI/Syntax/EditorScrollSync.swift` | 两个编辑器的垂直滚动同步 |

`CodeEditorView` 与 `EditorScrollSync` 放在 `QuickUI` 而不是插件里：任何需要「编辑器式输入 + 高亮」或「双栏同步滚动」的地方都能复用。

## 已知限制

- 见上面不变量里标为「既有行为」的条目：它们是当前实现的取舍，改之前先确认是有意为之。
- **横向滚动不同步**，只同步纵向。左右列宽一致时影响很小。
- **行号按「逻辑行」算**：因为关闭了软换行，一行文本就是一屏一行，两者一致。
