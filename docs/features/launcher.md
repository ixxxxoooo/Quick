# 应用启动器（launcher）

主搜索入口。扫描系统已安装的应用，支持模糊搜索、使用频率排序与收藏。

`LauncherPlugin` 是唯一把 `AppIndex` 通过构造器注入的插件 —— 因为它是唯一需要
应用清单的插件，而 `AppIndex` 由 `AppCore` 拥有并异步刷新。

## 不变量

- **空查询最多返回 8 条，非空查询最多 20 条。** 首屏不能把几百个应用一次性铺出来：
  每个条目都要解码并渲染一个应用图标，全量返回会让面板首次显示卡住。
  改动这个上限前先测一次面板显隐耗时（预算 100 ms）。
- **空查询的候选顺序是「收藏优先，否则取索引前 8」。** 收藏为空时退化为索引顺序，
  这是刻意的 —— 没有收藏的新用户也该看到点东西，而不是一片空白。
- **`SearchableItem.id` 必须带有 `launcher.` 前缀。**
  - 应用项：`launcher.<bundleID>`
  - 直接 Shell：`launcher.shell.direct`
  - 自定义 Shell 命令：`launcher.cmd.<UUID>`
  - Shell 兜底：`launcher.shell.fallback`
- **直接以 `>` 开头的查询，进入直接 Shell 执行模式。** 单独返回一个 1.0 相关度的条目，回车后异步在 `/bin/zsh -l -c` 下执行并通过 HUD 显示输出反馈。
- **支持自定义应用别名与快捷键。** 用户在设置中配置的应用别名若完全匹配当前查询，直接以 1.0 最高相关度排在首位；模糊匹配别名亦能获得评分加权。
- **支持自定义 Shell 命令库与 Shell 兜底。** 搜索列表底部可展示 `$ <query>` 兜底执行项（受设置开关控制）。
- **面板快捷键与窗口操作遵循规范。** 主搜索窗口支持 `⌘,` 打开设置，`⌘W` 关闭面板；设置窗口支持 `⌘W` 关闭。搜索栏左下角不显示条目计数器。

## 内部结构

| 类型 | 职责 |
| --- | --- |
| `LauncherPlugin` | 插件入口，实现 `QuickPlugin`；搜索（应用、别名、Shell 与自定义命令）与排序逻辑 |
| `RankingStore` | 使用次数记录（bundleID → 次数），归一化成 0…1 的评分 |
| `FavoritesStore` | 收藏的 bundleID 列表，保持插入顺序 |
| `AppIndex` | 应用程序索引与扫描，支持动态自定义搜索范围配置 |
| `ShellCommandRunner` | 结构化后台异步执行 Shell 脚本并捕获 stdout/stderr/退出码 |
| `CustomCommand` | 用户自定义 Shell 命令数据结构 |
| `KeyShortcut` / `HotKeyService` | 全局热键与应用/操作绑定服务 |
| `LauncherView` | 插件在面板内的主视图 |

## 持久化

| 文件 / 存储键 | 内容 | 写入时机 |
| --- | --- | --- |
| `ranking.json` | `[bundleID: 使用次数]` | 记录使用后 **防抖 5 秒**落盘；停用时立即落盘 |
| `favorites.json` | `[bundleID]` | 每次增删**立即**落盘 |
| `SettingsStore` (UserDefaults) | 搜索范围、别名映射、自定义命令列表、Shell 回退开关 | 设置变更时立即写入 |
