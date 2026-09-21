# 超级面板（Super Panel）

感知当前项目上下文的命令面板。通过检测前台应用（Xcode、VS Code、
Cursor、Terminal 等）的当前项目路径，提供针对该项目的快速操作。

- 插件 id：`superPanel`
- 触发词：`sp`、`super`、`超级`

---

## 不变量

1. **项目检测只在前台应用变化时执行。** 同一应用重复触发返回缓存，
   不做文件系统轮询。
2. **Git 分支名通过读 `.git/HEAD` 文件获取。** 不跑 `git` 进程——
   进程创建开销是 5~20ms，读文件是微秒级，差两个数量级。
3. **操作列表按项目路径缓存。** 上下文不变不重算，`searchItems`
   只做内存过滤。
4. **项目类型检测是纯文件系统操作。** 只看标记文件是否存在
   （`Package.swift`、`package.json`、`Cargo.toml` 等），微秒级。

## 支持的项目类型

| 类型 | 标记文件 | 特有操作 |
| --- | --- | --- |
| Xcode / Swift | `Package.swift`、`*.xcodeproj` | swift build/test、运行 Scripts/*.sh |
| Node.js | `package.json` | npm/yarn/pnpm run（读 scripts 字段） |
| Python | `requirements.txt`、`pyproject.toml` | pytest、pip install |
| Rust | `Cargo.toml` | cargo build/run/test |
| Go | `go.mod` | go build/test/run |
| Java | `pom.xml`、`build.gradle` | maven/gradle build/test |
| 通用 | `.git` | 仅 Git + 文件操作 |

## 支持的 IDE

| 应用 | 检测方式 |
| --- | --- |
| Xcode | 窗口标题 |
| VS Code | 窗口标题 |
| Cursor | 窗口标题 |
| Zed | 窗口标题 |
| Sublime Text | 窗口标题 |
| JetBrains 系列 | 窗口标题 |
| Terminal | 窗口标题 |
| iTerm2 | 窗口标题 |

## 操作分类

- **Git**：分支信息、status、log、diff、pull、push
- **构建**：项目类型特定的构建/测试/运行命令
- **文件**：Finder 中打开、快速导航（README、.env、Makefile 等）
- **终端**：在终端中打开、运行命令
- **快捷**：复制路径、在其他 IDE 中打开

## 设置

| 键 | 类型 | 说明 |
| --- | --- | --- |
| `superPanel.autoDetect` | Bool | 自动检测前台应用的项目 |
| `superPanel.showGitActions` | Bool | 显示 Git 操作 |
| `superPanel.showBuildActions` | Bool | 显示构建命令 |
| `superPanel.showFileNav` | Bool | 显示文件导航 |
| `superPanel.preferredTerminal` | String | 首选终端应用 |
