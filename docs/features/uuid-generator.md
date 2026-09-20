# UUID 生成器（uuid-generator）

批量生成 UUID / GUID，可选大小写与连字符。参考 Fasty uuid-generator。

## 不变量

- **批量生成必须互不相同**：一次生成 N 个就是 N 个不同值（已用 100 个一批的测试锁定）。
- 大小写与连字符两项持久化在 `uuidGenerator.uppercase` / `uuidGenerator.removeDashes`，与设置页共用同一个键；改其中一边记得另一边读的是同一份值。
- 去掉连字符后长度是 32，保留时是 36（连字符在 8/13/18/23 位）。

## 内部结构

`Model/UUIDGeneratorLogic.swift` 是纯逻辑（Foundation only，可独立测），`UI/` 里是视图与 `AppStorage` 绑定的选项。

## 已知限制

见上面不变量里标为「既有行为」的条目：它们是当前实现的取舍，改之前先确认是有意为之。
