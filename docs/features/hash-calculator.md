# Hash 计算器（hash-calculator）

计算 MD5 / SHA-1 / SHA-256 / SHA-512。参考 Fasty hash-calculator。

## 不变量

- **两个入口语义不同，不要合并**：`digests(of:)` 对空输入返回 `[]`（界面靠它显示空状态），`digest(_:algorithm:)` 对空输入返回该算法的真实摘要（空串的 MD5 是 `d41d8cd98f00b204e9800998ecf8427e`）。
- 输出统一是小写十六进制。改大小写会破坏与外部工具对拍的结果。
- `Algorithm.allCases` 的顺序就是界面上的行顺序。

## 内部结构

`Model/HashCalculatorLogic.swift` 是纯逻辑（Foundation only，可独立测），`UI/` 里是视图与 `AppStorage` 绑定的选项。

## 已知限制

见上面不变量里标为「既有行为」的条目：它们是当前实现的取舍，改之前先确认是有意为之。
