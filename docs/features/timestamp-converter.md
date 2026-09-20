# 时间戳转换（timestamp-converter）

Unix 时间戳与日期互转。参考 Fasty timestamp-converter。

## 不变量

- **必须挡住非有限值与超大值**：`Double("inf")` 能解析成功，而 `Int(inf)` 会直接崩掉进程 —— 一个纯文本输入框不该有让 App 挂掉的能力。上限是 `maximumMagnitude`（1e15）。
- **毫秒判定取绝对值**：`abs(value) > millisecondsThreshold`。1970 年之前的毫秒时间戳是负数，只看 `> 1e12` 会把它们当秒处理，差一千倍。
- **时区必须注入**：模型不读 `TimeZone.current`，显示与无时区日期的解析都用传入的时区，否则测不了。ISO 8601 一行固定输出 UTC。
- 只看 `dateFormats` 里列出的 5 种日期格式，其余一律当作无法识别。

## 内部结构

`Model/TimestampConverterLogic.swift` 是纯逻辑（Foundation only，可独立测），`UI/` 里是视图与 `AppStorage` 绑定的选项。

## 已知限制

见上面不变量里标为「既有行为」的条目：它们是当前实现的取舍，改之前先确认是有意为之。
