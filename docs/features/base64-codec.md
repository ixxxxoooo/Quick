# Base64 编解码（base64-codec）

文本与 Base64 互转。参考 Fasty base64-codec。

## 不变量

- **空串是合法的 Base64**：`decode("")` 返回 `""` 而不是报错。界面靠 `!input.isEmpty` 提前返回，所以走不到这条路径 —— 测的时候别把它当成错误用例。
- 解码失败分两种：`Failure.invalidBase64`（不是合法 Base64）与 `Failure.invalidUTF8`（解出来不是 UTF-8 文本）。
- `Data(base64Encoded:)` 对填充敏感：缺 `=` 会被判为非法，这是有意的严格。

## 内部结构

`Model/Base64CodecLogic.swift` 是纯逻辑（Foundation only，可独立测），`UI/` 里是视图与 `AppStorage` 绑定的选项。

## 已知限制

见上面不变量里标为「既有行为」的条目：它们是当前实现的取舍，改之前先确认是有意为之。
