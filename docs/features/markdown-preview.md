# Markdown 预览（markdown-preview）

实时 Markdown 编辑与预览。参考 Fasty markdown-preview。

## 不变量

- **渲染交给 SwiftUI**：预览就是 `Text(LocalizedStringKey(input))`，这个插件**没有自己的 Markdown 解析器**，所以 GFM 的部分语法（表格、任务列表）取决于系统实现。
- `Model/` 里唯一真实的逻辑是工具栏的字符数（`characterCountLabel`），空输入返回 nil（不显示）。不要为了「有东西可测」而在这里造一个解析器。

## 内部结构

`Model/MarkdownPreviewLogic.swift` 是纯逻辑（Foundation only，可独立测），`UI/` 里是视图与 `AppStorage` 绑定的选项。

## 已知限制

见上面不变量里标为「既有行为」的条目：它们是当前实现的取舍，改之前先确认是有意为之。
