# JSON 格式化（json-formatter）

格式化与压缩 JSON，带语法高亮。参考 Fasty json-formatter。

## 不变量

- **压缩永远输出单行**，不受缩进设置影响 —— 缩进只作用于「格式化」。
- **解析用 `JSONSerialization`**，所以 JSON5、尾逗号、注释都不支持；无效输入返回 `Failure.invalidJSON`，界面显示「无效的 JSON」而不是原样回显。
- `Outcome.nodeCount` 与 `byteSize` 都来自同一次解析，不要为了显示再去解析一遍。
- 缩进设置键是 `jsonFormatter.indent`，与设置页 `JSONFormatterFeatureSection` 共用同一个 `@AppStorage` 键。

## 内部结构

`Model/JSONFormatterLogic.swift` 是纯逻辑（Foundation only，可独立测），`UI/` 里是视图与 `AppStorage` 绑定的选项。

## 已知限制

见上面不变量里标为「既有行为」的条目：它们是当前实现的取舍，改之前先确认是有意为之。
