# 超级面板（Super Panel）

对齐 Fasty 的双态超级面板：识别剪贴板内容给出即时动作；空白时提供工作台；
并保留 IDE 前台项目检测。

- 插件 id：`superPanel`
- 触发词：`sp`、`super`、`超级`、`超级面板`

---

## 不变量

1. **面板有三态：上下文 / 工作台 / 项目。** 打开时若剪贴板有文本，默认进上下文；
   否则进工作台。项目页由用户切换或从工作台项目卡片进入。
2. **智能预览是纯逻辑。** `SmartPreviewDetector` 不依赖 AppKit，路径存在性通过
   注入的闭包判断，测试可脱离磁盘。
3. **项目检测只在前台应用变化时执行。** 同一应用重复触发返回缓存，
   不做文件系统轮询。
4. **Git 分支名通过读 `.git/HEAD` 文件获取。** 不跑 `git` 进程。
5. **操作列表按项目路径缓存。** 上下文不变不重算。
6. **插件之间只通过 `EventBus` 跳转。** 打开翻译 / JSON / 颜色等工具走
   `NavigateEvent`，不直接 `import` 其他插件。

## 智能预览类型（上下文）

| 类型 | 示例 | 主要动作 |
| --- | --- | --- |
| 网址 | `https://…` | 打开、复制 |
| 文件路径 | `/Users/…`、`~/…` | Finder、终端、复制路径 |
| 颜色 | `#FF5500` | 复制 HEX、打开颜色工具 |
| 时间戳 | `1700000000` | 复制格式化时间、打开时间戳工具 |
| Base64 | 可解码明文 | 复制解码结果、打开 Base64 工具 |
| URL 编码 | `%E4%BD%A0` | 复制解码结果、打开 URL 工具 |
| 算式 | `1+2*3` | 复制结果 |
| 邮箱 / 电话 / IP | … | 复制 / mailto / 网络工具 |
| JSON | `{…}` | 打开 JSON 格式化 |
| 中英文本 | 短句 | 打开翻译 |

## 工作台

默认常用工具（对齐 Fasty）：截图、剪贴板、翻译、AI、备忘、计算、监控、JSON。
可在设置中关闭工具网格或剪贴板预览。

## 项目

| 类型 | 标记文件 | 特有操作 |
| --- | --- | --- |
| Xcode / Swift | `Package.swift`、`*.xcodeproj` | swift build/test、Scripts |
| Node.js | `package.json` | npm/yarn/pnpm scripts |
| Python | `requirements.txt`、`pyproject.toml` | pytest、pip |
| Rust | `Cargo.toml` | cargo build/run/test |
| Go | `go.mod` | go build/test/run |
| Java | `pom.xml`、`build.gradle` | maven/gradle |
| 通用 | `.git` | Git + 文件操作 |

## 设置

| 键 | 类型 | 说明 |
| --- | --- | --- |
| `superPanel.autoDetect` | Bool | 自动检测前台应用的项目 |
| `superPanel.showGitActions` | Bool | 显示 Git 操作 |
| `superPanel.showBuildActions` | Bool | 显示构建命令 |
| `superPanel.showFileNav` | Bool | 显示文件导航 |
| `superPanel.preferredTerminal` | String | 首选终端应用 |
| `superPanel.showClipboard` | Bool | 工作台显示剪贴板预览 |
| `superPanel.showQuickTools` | Bool | 工作台显示常用工具 |
