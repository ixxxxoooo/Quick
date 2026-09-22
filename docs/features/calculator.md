# 计算器（calculator）

在主搜索框输入表达式即时求值，或进入「计算稿纸」逐条记录、回看与复制计算结果。

## 不变量

- **历史是持久化的真表**（`calc_history`，由 `CalculatorPlugin.storageMigrations` 声明），
  跨启动保留；上限 `CalcHistoryStore.maxEntries`（200），超出按最新剪枝，去重、插入、
  剪枝在同一次事务里完成。
- **同一个表达式再算一次不新增记录**，而是把它提到最前并刷新结果 —— 稿纸上重复写同一行没有意义。
- **历史保存的是当时格式化好的结果字符串，不在展示时重算。** 小数位数 / 千分位是设置页随时可改的，
  重算会让历史里的 `0.67` 变成 `0.666667`，历史就不再是历史。
- **空白表达式不记录。**
- **主搜索回车与计算稿纸输入栏回车记的是同一条历史**：两条路径共用插件里的同一个
  `CalcHistoryStore` 实例。主搜索回车同时沿用 `autoCopy` 决定是否复制。
- 主搜索是否求值由 `accepts` 的便宜闸门（`CalcEngine.looksLikeExpression`）决定；不像表达式不进求值。

## 内部结构

| 文件 | 职责 |
| --- | --- |
| `Model/CalcEngine.swift` | 纯计算：词法 + 递归下降解析，单位换算。零环境依赖 |
| `Model/CalcPreferences.swift` | 显示选项（小数位 / 千分位）与格式化 |
| `Model/CalcHistoryEntry.swift` | 一条历史（表达式 + 结果 + 时间） |
| `Service/CalcHistoryStore.swift` | 历史持久化（SQLite），落库后重读缓存 |
| `UI/CalculatorView.swift` | 计算稿纸：历史列表 + 输入栏 + 实时结果 |

## 交互

- 点历史行 = 复制结果（发 `CopyToClipboardEvent`，HUD 由宿主提示）。
- 悬停一行出现复制 / 删除按钮；右键菜单同样有这两项。
- 顶部工具条显示记录数并可一键清空。
- 输入栏边打边显示结果；回车把当前算式记进稿纸并清空输入，焦点留在输入栏。
