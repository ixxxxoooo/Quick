# features/ — 功能插件的不变量

每个功能插件一份，**文件名就是插件 id**（`launcher.md`、`clipboard.md`……）。

每份文档以 `## 不变量` 开头，写明「改这个插件前必须知道的事」——
那些从代码里看不出来、但破坏了一定会出问题的约束。它不是代码的复述，
而是代码无法自己表达的那部分知识。

## 现状

| 插件 id | 文档 | 状态 |
| --- | --- | --- |
| `launcher` | [launcher.md](launcher.md) | 已写 |
| `clipboard` | [clipboard.md](clipboard.md) | 已写 |
| `weather` | [weather.md](weather.md) | 已写（定位权限策略是重点） |
| 11 个开发者工具 | [json-formatter](json-formatter.md) · [sql-formatter](sql-formatter.md) · [base64-codec](base64-codec.md) · [url-codec](url-codec.md) · [uuid-generator](uuid-generator.md) · [hash-calculator](hash-calculator.md) · [timestamp-converter](timestamp-converter.md) · [word-counter](word-counter.md) · [text-diff](text-diff.md) · [markdown-preview](markdown-preview.md) · [color-compare](color-compare.md) | 已写（从 `devtools` 容器拆出后补上，重点是各自的既有取舍） |
| 其余 13 个 | — | 待补。新增或深改一个插件时同步补上 |

## 模板

```markdown
# <插件名>（<plugin id>）

一句话说明这个插件做什么。

## 不变量
- 必须成立、破坏就会出问题的事。这是本文档最重要的部分。

## 内部结构
Model / Service / UI 各自负责什么，关键类型的作用。

## 持久化
存了什么、存在哪、格式版本、损坏时怎么降级。

## 已知限制
明确不支持的场景，避免被当 bug 修。
```

## 相关的通用规则

插件契约本身（`QuickPlugin` 协议、注册流程、事件总线、结果相关度约定）在
[../architecture.md](../architecture.md)，不在这里重复。
