# 开发指南

本文件回答「命令是什么、怎么调试、提交怎么走」。规则本身看 [../AGENTS.md](../AGENTS.md)。

---

## 1. 环境要求

| 工具 | 版本 | 说明 |
| --- | --- | --- |
| macOS | 26+ | 部署目标就是 26.0，只支持当前稳定版 |
| Xcode | 26+ | 提供 Swift 6 工具链与 `swift-format` |
| Swift | 6.0 语言模式 | 严格并发 `complete` |
| [XcodeGen](https://github.com/yonaskolb/XcodeGen) | 最新 | `brew install xcodegen`，用于生成工程 |
| SwiftLint（可选） | 最新 | `brew install swiftlint`。未安装时 `Scripts/lint.sh` 会跳过并明确报告 |

**首次克隆后执行一次：**

```bash
./Scripts/setup.sh
```

它会启用版本控制的 git 钩子（`git config core.hooksPath .githooks`），
这样每次提交都会自动跑测试。**不执行这一步，质量门禁就是不存在的。**

---

## 2. 日常命令

```bash
./Scripts/format.sh          # 用 swift-format 就地格式化全部 Swift 文件
./Scripts/lint.sh            # 排版检查（swift-format）+ 语义检查（swiftlint，若已安装）
./Scripts/lint.sh --changed  # 只检查本次暂存的文件（pre-commit 用）
./Scripts/run-tests.sh       # 跑全部包的测试
./Scripts/run-tests.sh QuickCore ModuleCalculator   # 只跑指定的包
./Scripts/build.sh           # 构建 Debug .app
./Scripts/build.sh --run     # 构建并启动
./Scripts/logs.sh            # 实时跟踪 Quick 的日志
./Scripts/logs.sh --errors   # 只看近 1 小时的 warning / error / fault
./Scripts/new-module.sh ModuleFoo   # 生成新功能模块骨架
```

**提交前的最小动作**：`./Scripts/format.sh && ./Scripts/run-tests.sh`。
钩子会替你跑一次测试，但先自己跑能省一轮往返。

---

## 3. 构建

### 工程是生成的

`project.yml` 是唯一真相，`Quick.xcodeproj` 由它生成但**要提交**（打开工程不该依赖
本机是否装了 xcodegen）。

**改了 `project.yml` 之后必须：**

```bash
xcodegen generate
git add project.yml Quick.xcodeproj     # 两边一起提交
```

**永远不要手工编辑 `Quick.xcodeproj/project.pbxproj`** —— 下次生成会覆盖掉。

### 加依赖包时改哪两处

新增一个 `Packages/ModuleXxx` 需要在 `project.yml` 里改两个地方，漏一个就会编译不过：

```yaml
packages:                                   # ① 声明包
  ModuleXxx:
    path: Packages/ModuleXxx

targets:
  Quick:
    dependencies:                           # ② 让 app 依赖它
      - package: ModuleXxx
```

### 命令行构建

```bash
./Scripts/build.sh
# 等价于
xcodebuild -project Quick.xcodeproj -scheme Quick \
           -configuration Debug -destination 'platform=macOS' build
```

构建产物在 Xcode 的 DerivedData 里；`./Scripts/build.sh --run` 会构建、找到 `.app`、
启动它并把路径打出来。

### 单独构建某个包（快得多，用于验证编译）

```bash
swift build --package-path Packages/QuickUI
```

---

## 4. 调试

### 日志优先

**排问题的第一动作是看日志，不是加断点。** 本项目的日志要求覆盖所有关键路径
（见 [logging.md](logging.md)），所以大部分问题应当能直接看出来。

```bash
./Scripts/logs.sh                       # 实时全部
./Scripts/logs.sh --errors              # 近 1 小时的问题
log stream --predicate 'subsystem == "com.ygw.quick" AND category == "palette"' --level debug
```

`subsystem` 就是 bundle id：`com.ygw.quick`。

**注意**：当前 Debug 与 Release 共用这一个 bundle id，所以本地调试的日志与已安装版本
混在同一子系统里 —— 用 `Scripts/logs.sh` 看时可以按 category 区分（`app` 是应用层，
`module.*` 是各模块）。真正的 Debug 独立频道尚未实施，见 §8。

### 启动参数

| 参数 | 作用 |
| --- | --- |
| `-showPalette` | 启动后立即显示面板，省掉手按快捷键 |

```bash
open -a "$(./Scripts/build.sh --path)" --args -showPalette
```

### 面板不出现时按顺序排查

1. **进程活着吗** —— `pgrep -fl Quick`。没活着先看崩溃报告。
2. **热键注册成功了吗** —— 日志里应有「已注册全局快捷键 ⌥Space」。
   失败通常是组合键被别的应用占用。
3. **窗口真的存在吗** —— `isVisible == true` 不能证明窗口在屏幕上。
   用 `CGWindowListCopyWindowInfo` 或肉眼看。
4. **应用失活把面板关掉了？** —— 确认 `hidesOnDeactivate == false`
   （`PalettePanelTests` 已覆盖这条）。
5. **CPU 打满？** —— 大概率是 AttributeGraph 重建死循环。
   检查是否有人给 `PaletteCoordinator` 加了 `@Observable`，或在 `body` 里创建
   `NSImage`。这是本项目踩过的坑（提交 `304af38`）。

### 调试用的分布式通知

在应用内用 `DistributedNotificationCenter` 监听 `com.ygw.quick.togglePalette` 来切换面板。

**不要用 `notifyutil -p`** —— 那是另一套 notify API，和 `DistributedNotificationCenter`
不互通，你会以为代码没生效。

---

## 5. 提交

### 钩子做了什么

`.githooks/` 由版本控制，通过 `Scripts/setup.sh` 激活：

| 钩子 | 检查 |
| --- | --- |
| `pre-commit` | ① 对暂存的文件跑 `swift-format` 排版检查 ② **跑全量测试** |
| `commit-msg` | 校验 Conventional Commits 格式，并拒绝非 ASCII 主题行（等价于强制英文） |

**测试失败就拒绝提交。** 这是刻意的：本项目的规则是「每次提交前必须跑完测试」。

**不要用 `git commit --no-verify` 绕过。** 如果确实需要（例如紧急修复一个只改文档的提交），
在推送前必须补跑一次 `./Scripts/run-tests.sh`。

### 提交信息格式

**一律英文。** 完整规则见 [../AGENTS.md#提交规范](../AGENTS.md)。

```
<type>(<scope>): <祈使语气的小写英文描述>

<正文：为什么这么改>
```

示例：

```
feat(clipboard): add pinning with a 30-entry history cap
fix(palette): keep the panel on screen when the app deactivates
perf(launcher): score app names once per refresh instead of per keystroke
refactor(quickui): move every hardcoded literal into DesignTokens
docs(ui): record the palette geometry and its tokens
```

一个提交只做一件事。规则文档、代码、测试如果在同一个逻辑改动里，就放在同一个提交 ——
本项目要求「该改的文档在同一个提交里改掉」。

### 分支

- `main` 始终可构建、可运行、测试全绿。
- 功能开发用短生命周期分支，命名 `<type>/<简短描述>`：
  `feat/clipboard-pinning`、`fix/palette-focus-restore`。
- 合并前 rebase 到最新 `main`，保证历史是线性的。

---

## 6. 新增功能模块

完整流程见 [../AGENTS.md#新增一个功能模块](../AGENTS.md)。命令侧就是：

```bash
./Scripts/new-module.sh ModuleFoo
xcodegen generate
./Scripts/run-tests.sh ModuleFoo
```

脚手架会生成：

```
Packages/ModuleFoo/
├── Package.swift                       # 已声明依赖与 testTarget
├── Sources/ModuleFoo/
│   ├── FooModule.swift                 # 实现 QuickModule 的骨架
│   ├── Model/
│   ├── Service/
│   └── UI/
└── Tests/ModuleFooTests/
    └── FooModuleTests.swift            # 非空测试 —— 避免 testTarget 空导致测试失败
```

**别忘的三步**：在 `AppCore.registerModules()` 注册、在 `project.yml` 加两处、
在 `docs/features/<id>.md` 写不变量。

---

## 7. 数据与文件位置

全部通过
[`AppPaths`](../Packages/QuickPlatform/Sources/QuickPlatform/System/AppPaths.swift)：

| 用途 | 位置 |
| --- | --- |
| 模块数据 | `~/Library/Application Support/<bundle id>/<module id>/` |
| 缓存 | `~/Library/Caches/<bundle id>/` |
| 日志 | 统一日志系统（不是文件），见 [logging.md](logging.md) |

**Debug 与 Release 目前共用同一个 bundle id（`com.ygw.quick`）**，所以本地跑的构建
和已安装版本共用同一份数据、日志与 TCC 授权。给 Debug 配一个独立 bundle id
（`com.ygw.quick.dev`）可以彻底隔离，代价是本地构建需要重新授予辅助功能权限。
**这是建议的改进，尚未实施** —— 实施前不要假设隔离已经生效。

---

## 8. 发布

发布链路尚未建立（没有签名身份、没有 DMG 脚本、没有 CI 归档）。在补齐之前，
「发布」= 用 Xcode 归档 Release 配置并手工分发。

补齐发布链路时需要做的事情（写在这里避免遗漏）：

1. **Debug 独立频道**：给 `project.yml` 的 Debug 配置一个独立
   `PRODUCT_BUNDLE_IDENTIFIER`（如 `com.ygw.quick.dev`），让本地构建拥有自己的
   偏好、缓存、日志子系统与 TCC 授权，不再和已安装版本互相污染。
   同时把 `AppPaths` 从写死的 `"Quick"` 改成基于 `Bundle.main.bundleIdentifier`，
   并恢复 `Scripts/logs.sh` 的 `--dev` 开关（目前因为只有一个 subsystem 已移除）。
2. **稳定的自签名身份**：macOS 的 TCC 权限认签名，每次重建都换签名会导致
   辅助功能权限反复失效。需要一个固定的自签名证书。
3. **Release 构建设置**：`ENABLE_HARDENED_RUNTIME`、剥离符号、
   `DEPLOYMENT_POSTPROCESSING`。
4. **DMG 打包脚本**。
5. **CI 归档工作流**（当前 `.github/workflows/ci.yml` 只做测试、lint 与构建校验）。
