# 应用启动器（launcher）

主搜索入口。扫描系统已安装的应用，支持模糊搜索、使用频率排序与收藏。

`LauncherModule` 是唯一把 `AppIndex` 通过构造器注入的模块 —— 因为它是唯一需要
应用清单的模块，而 `AppIndex` 由 `AppCore` 拥有并异步刷新。

## 不变量

- **空查询最多返回 8 条，非空查询最多 20 条。** 首屏不能把几百个应用一次性铺出来：
  每个条目都要解码并渲染一个应用图标，全量返回会让面板首次显示卡住。
  改动这个上限前先测一次面板显隐耗时（预算 100 ms）。
- **空查询的候选顺序是「收藏优先，否则取索引前 8」。** 收藏为空时退化为索引顺序，
  这是刻意的 —— 没有收藏的新用户也该看到点东西，而不是一片空白。
- **`SearchableItem.id` 必须是 `launcher.<bundleID>`。** `id` 是列表的 `Identifiable`
  主键，重复会让 SwiftUI 的行错乱。用 bundleID 而不是应用名，因为应用名会重复
  （两个不同路径的同名应用）。
- **相关度是混合分：`fuzzyScore * 0.7 + ranking * 0.3`。** `AppIndex.search` 已按
  名称相关度排过序，但最终进列表的分数必须叠加使用频率，否则常用应用永远排在
  名称更匹配的陌生应用后面。两个权重不是一个可以随手调的比例 —— 改它等于改产品的
  核心手感。
- **`activate()` 必须 `load()` 两个 Store，`deactivate()` 必须 `save()` RankingStore。**
  `FavoritesStore` 的每次增删都立即落盘（见下），所以停用时不必再存。
- **`searchItems` 必须是纯查询。** 它会在每次按键（防抖后）被调用，不允许在里面
  启停监听、写盘、或调用 `appIndex.refresh()`。

## 内部结构

| 类型 | 职责 |
| --- | --- |
| `LauncherModule` | 模块入口，实现 `QuickModule`；搜索与排序逻辑都在这里 |
| `RankingStore` | 使用次数记录（bundleID → 次数），归一化成 0…1 的评分 |
| `FavoritesStore` | 收藏的 bundleID 列表，保持插入顺序 |
| `LauncherView` | 模块在面板内的主视图（**目前面板外壳尚未接入模块视图**） |

排序的输入有两个来源：`AppIndex`（名称匹配，只负责过滤与粗排）与 `RankingStore`
（使用频率，负责个性化）。两者在 `searchItems` 里合成最终 `relevance`。

## 持久化

| 文件 | 内容 | 写入时机 |
| --- | --- | --- |
| `ranking.json` | `[bundleID: 使用次数]` | 记录使用后 **防抖 5 秒**落盘；停用时立即落盘 |
| `favorites.json` | `[bundleID]` | 每次增删**立即**落盘 |

路径走 `AppPaths.moduleData("launcher")`。

- 两者的 `init(storageURL:)` 接收可选路径，默认走 `AppPaths`。
  **测试必须传临时目录**，否则会污染用户真实数据。
- 解码失败一律降级为空记录并记 `.error`，**不让模块起不来**。
  用户的历史记录不该因为一个损坏的 JSON 就让整个启动器失效。

## 已知限制

- **不做拼音搜索。** 类文档注释里提到过拼音匹配，但当前实现只有
  `String.fuzzyScore` 的子序列匹配 —— 对中文它是**字符**子序列，不是拼音。
  所以输入 `wx` 不会命中「微信」，输入 `weixin` 也不会。想要拼音需要一张汉字到
  拼音的映射表，属于未实现的功能，不是 bug。
- **模糊匹配的漏判与误判是子序列算法的固有行为。** `fuzzyScore` 的阶梯是
  完全 `1.0` / 前缀 `0.9` / 包含 `0.7` / 子序列 `0.4`，且 `fuzzyMatch` 是纯顺序子序列 ——
  输入 `gc` 会命中 `Google Chrome`，也会命中 `Basic Config`。这是有意的取舍。
- **不按使用频率衰减。** `RankingStore` 只累计次数，不做时间衰减，
  所以几年前常用、现在不用的应用会长期占据高位。
- **不监听应用目录变化。** `AppIndex.refresh()` 只在启动时跑一次，新装的应用要重启才出现。
- **不索引 `~/Applications` 之外的用户目录**，也不索引已挂载磁盘上的应用。
- `makeSettingsView()` 返回 `nil`：启动器目前没有设置页，收藏也没有 UI 入口
  （`FavoritesStore` 已实现并有测试，但没有任何界面在调用 `add` / `remove`）。
