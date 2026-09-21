# 应用启动器（launcher）

主搜索入口。扫描系统已安装的应用，支持模糊搜索、拼音匹配、使用频率排序与收藏。

`LauncherPlugin` 是唯一把 `AppIndex` 通过构造器注入的插件 —— 因为它是唯一需要
应用清单的插件，而 `AppIndex` 由 `AppCore` 拥有并异步刷新。

## 不变量

- **匹配走 `QuickCore/Search` 的匹配器，不要在这里自己写比较。** 阶梯是
  完全 `1.0` > 前缀 `0.9` > 包含 `0.7` > 子序列 `0.35…0.65`；汉字额外按拼音命中
  （全拼 `weixin`、首字母 `wx`），但拼音整体压在字面之下。
  改名这套刻度就会动全盘排序，插件是拿它当刻度用的（这里再乘 0.7 叠使用频率）。
- **查询词每次按键只折叠一次，候选的匹配形态跟数据一起存。** 索引有上百条应用，
  在循环里重新折叠或转写拼音会直接吃掉按键预算。所以 `AppEntry` 在构造时
  （扫描线程上）就算好 `matchText`，循环里只调用 `matchQuery.score(entry.matchText)`。
- **空查询最多返回 20 条，非空查询最多 20 条。** 首屏不能把几百个应用一次性铺出来：
  每个条目都要解码并渲染一个应用图标，全量返回会让面板首次显示卡住。
  改动这个上限前先测一次面板显隐耗时（预算 100 ms）。
- **匹配不到就一条都不返回。** 相关度为 0 的应用不进结果 —— 兜底条目只是列表底部
  那个 `$ <query>`，不要用「全给 0」代替过滤。
- **空查询的候选顺序是「收藏优先，否则按使用频率」—— 但这只决定候选，不决定最终顺序。**
  首屏在聚合之后还会被 `PaletteCoordinator.promotingRecents` 用跨插件的 `UsageHistory`
  重排一次，最近使用过的条目会被提到最前。收藏为空时退化为频率顺序，这是刻意的 ——
  没有收藏的新用户也该看到点东西，而不是一片空白。**排查首屏顺序时不要只看这个文件。**
- **`defaultItems()` 必须返回空。** 首屏的主体就是这里给出的应用列表；
  默认实现会额外贡献「触发词裸查询的第一条」，那会让首屏多出一条多余的应用条目
 （`LauncherPlugin` 因此覆盖它）。
- **`SearchableItem.id` 必须带有 `launcher.` 前缀。**
  - 应用项：`launcher.<bundleID>`
  - 直接 Shell：`launcher.shell.direct`
  - 自定义 Shell 命令：`launcher.cmd.<UUID>`
  - Shell 兜底：`launcher.shell.fallback`
- **直接以 `>` 开头的查询，进入直接 Shell 执行模式。** 单独返回一个 1.0 相关度的条目，回车后异步执行并通过 HUD 显示输出反馈。
- **收 stdout/stderr 用临时文件，不能用 `Pipe`。** 执行流程是 `run()` → `waitUntilExit()` → 读输出，
  管道在这个顺序下必然死锁：读端一直没人在读，子进程写满管道缓冲区（macOS 上 64 KiB）就阻塞在
  write 上，而父进程正等着它退出。任何输出超过 64 KiB 的命令都会把这次执行永久挂住，且不留日志。
  临时文件没有这个上限，退出后按上限读尾部即可（`StreamCapture`，与 Tinycast 同向）。
- **执行放在专用并发队列上，不要用 `Task.detached`。** `waitUntilExit` 会阻塞线程，而 Swift
  协作线程池只有核心数个线程，一条卡住的命令会让面板的其他异步活一起排队。
- **`-lc` 只读 `.zprofile`；要别名或 `.zshrc` 里的 PATH 就必须 `-ilc`。** zsh 只让交互式 shell
  source `.zshrc`，所以别名和 nvm / pyenv 那类 PATH 段默认都不在 —— 用户在自己终端里好好的命令
  会退化成「command not found」。分界线是「这句话是谁说的」：用户当场敲的（`>` 直执行、终端兜底）
  走 `-ilc`，他打的 `ll` 指的就是自己的别名；存下来的自定义命令默认 `-lc`，由用户在编辑那条命令时
  用 `loadsShellEnvironment` 自己决定值不值那份配置加载时间。
- **工作目录不存在就拒绝执行。** 在一个意料之外的地方跑用户的命令，比不跑更糟。`~` 要展开，
  目录要校验（`resolvedWorkingDirectory`），`cd` 那行照旧 `|| exit 1`。
- **Shell 兜底走「写脚本文件 + LaunchServices 打开」，不要改回 AppleScript。** 兜底项把命令
  写进一个 `.command` 文件，再交给用户选定的终端（`ShellCommandRunner.runInTerminal`）。
  `tell application "Terminal" … do script …` 那条老路有两个静默失败：它要「自动化」权限
  （按代码签名授予，dev 版每次重新构建都可能失效），而命令文本会被拼进 AppleScript 源码，
  带 `"` 或换行就把脚本本身拆坏 —— 表现都是「终端打开了、命令没跑」。
  它与 `>` 模式的区别只是要不要一个真终端：`>` 在后台跑、输出收进 HUD；兜底要让用户看见
  完整交互，所以交给终端。选定的终端没装或不处理 `.command`（Warp / Kitty 之类）时回落到
  系统默认终端，而不是把命令丢掉。
- **终端脚本末尾必须把会话交给交互式 shell（`if [ -t 0 ]; then exec /bin/zsh -il; fi`）。**
  没有这一句，命令一返回登录 shell 就退出，终端随即结束会话（默认配置是「干净退出即关窗」），
  用户连输出都来不及看 —— 表现是窗口一闪就没，看起来像功能坏了。脚本 shebang 也用 `-il`
  而不是 `-l`，理由同上一条。`-t 0` 守卫保证只有真的挂在终端上时才交接：非终端调用
  （测试、被别的程序打开）仍然一次性执行，退出码不受影响。
- **支持自定义应用别名与快捷键。** 别名与显示名各算一次匹配分，取二者较高者 ——
  别名完全匹配时就是 1.0，自然排在首位。
- **支持自定义 Shell 命令库与 Shell 兜底。** 搜索列表底部可展示 `$ <query>` 兜底执行项（受设置开关控制）。
- **面板快捷键与窗口操作遵循规范。** 主搜索窗口支持 `⌘,` 打开设置，`⌘W` 关闭面板；设置窗口支持 `⌘W` 关闭。搜索栏左下角不显示条目计数器。

## 内部结构

| 类型 | 职责 |
| --- | --- |
| `LauncherPlugin` | 插件入口，实现 `QuickPlugin`；搜索（应用、别名、Shell 与自定义命令）与排序逻辑 |
| `RankingStore` | 使用次数记录（bundleID → 次数），归一化成 0…1 的评分 |
| `FavoritesStore` | 收藏的 bundleID 列表，保持插入顺序 |
| `AppIndex` | 应用程序索引与扫描，支持动态自定义搜索范围配置；每个条目在构造时算好名称的匹配形态 |
| `ShellCommandRunner` | 后台执行 Shell 命令（临时文件收 stdout/stderr）、打开终端执行 |
| `CustomCommand` | 用户自定义 Shell 命令数据结构 |
| `KeyShortcut` / `HotKeyService` | 全局热键与应用/操作绑定服务 |
| `LauncherView` | 插件在面板内的主视图 |

## 持久化

宿主只提供数据库句柄，两张表的结构由 `LauncherPlugin.storageMigrations` 声明。

| 表 | 内容 | 写入时机 |
| --- | --- | --- |
| `usage_stats`（迁移 `launcher.usage_stats`） | `item_id` → `count`、`last_used` | 每次启动应用**单行自增**，不再防抖 |
| `favorites`（迁移 `launcher.favorites`） | `item_id` + `sort_order`、`created_at` | 每次增删立即写入，顺序由 `sort_order` 决定 |
| `SettingsStore` (UserDefaults) | 搜索范围、别名映射、自定义命令列表、Shell 回退开关 | 设置变更时立即写入 |
