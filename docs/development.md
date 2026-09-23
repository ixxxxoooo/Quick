# 开发指南

本文件回答「命令是什么、怎么调试、提交怎么走」。规则本身看 [../AGENTS.md](../AGENTS.md)。

---

## 1. 环境要求

| 工具 | 版本 | 说明 |
| --- | --- | --- |
| macOS | 26+ | 部署目标就是 26.0，只支持当前稳定版 |
| Xcode | 26+ | 提供 Swift 6 工具链 |
| Swift | 6.0 语言模式 | 严格并发 `complete` |
| [XcodeGen](https://github.com/yonaskolb/XcodeGen) | 最新 | `brew install xcodegen`，用于生成工程 |

**首次克隆后执行一次：**

```bash
./Scripts/setup.sh
```

它会启用版本控制的 git 钩子（`git config core.hooksPath .githooks`），
这样每次提交都会自动跑测试。**不执行这一步，质量门禁就是不存在的。**

---

## 2. 日常命令

```bash
./Scripts/run-tests.sh       # 跑全部包的测试
./Scripts/run-tests.sh QuickCore PluginCalculator   # 只跑指定的包
./Scripts/build.sh           # 构建 Debug .app
./Scripts/build.sh --run     # 构建并启动（轻量；日常改动请用 restart.sh）
./Scripts/restart.sh         # 构建 + 杀旧进程 + 启动新实例（改完必跑）
./Scripts/restart.sh --show  # 同上，启动后立刻弹出面板
./Scripts/restart.sh --no-build  # 只重启，不重新编译
./Scripts/logs.sh            # 实时跟踪 Quick 的日志
./Scripts/logs.sh --errors   # 只看近 1 小时的 warning / error / fault
./Scripts/new-plugin.sh PluginFoo   # 生成新功能插件骨架
```

**提交前的最小动作**：`./Scripts/run-tests.sh`。
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

新增一个 `Packages/PluginXxx` 需要在 `project.yml` 里改两个地方，漏一个就会编译不过：

```yaml
packages:                                   # ① 声明包
  PluginXxx:
    path: Packages/PluginXxx

targets:
  Quick:
    dependencies:                           # ② 让 app 依赖它
      - package: PluginXxx
```

### 命令行构建

```bash
./Scripts/build.sh
# 等价于
xcodebuild -project Quick.xcodeproj -scheme Quick \
           -configuration Debug -destination 'platform=macOS' build
```

构建产物在固定的 `build/DerivedData` 里。**改完代码后请跑：**

```bash
./Scripts/restart.sh         # 构建 → 杀旧进程 → 启动新实例
./Scripts/restart.sh --show  # 启动后立刻弹出面板（省掉手按 ⌥Space）
```

只构建不启动用 `./Scripts/build.sh`；`build.sh --run` 也能启动，但杀进程不如
`restart.sh` 稳（后者会等到旧进程真正退出）。

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
./Scripts/logs.sh                       # 实时正式版（com.ixxxxoooo.quick）
./Scripts/logs.sh --dev                 # 实时 Debug 频道（com.ixxxxoooo.quick.dev）
./Scripts/logs.sh --errors              # 近 1 小时的问题
log stream --predicate 'subsystem == "com.ixxxxoooo.quick.dev" AND category == "palette"' --level debug
```

`subsystem` 就是 bundle id。Debug 与 Release 已隔离，见 §8。

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

在应用内用 `DistributedNotificationCenter` 监听 `com.ixxxxoooo.quick.togglePalette` 来切换面板。

**不要用 `notifyutil -p`** —— 那是另一套 notify API，和 `DistributedNotificationCenter`
不互通，你会以为代码没生效。

---

## 5. 提交

### 钩子做了什么

`.githooks/` 由版本控制，通过 `Scripts/setup.sh` 激活：

| 钩子 | 检查 |
| --- | --- |
| `pre-commit` | **跑全量测试** |
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

## 6. 新增功能插件

完整流程见 [../AGENTS.md#新增一个功能插件](../AGENTS.md)。命令侧就是：

```bash
./Scripts/new-plugin.sh PluginFoo
xcodegen generate
./Scripts/run-tests.sh PluginFoo
```

脚手架会生成：

```
Packages/PluginFoo/
├── Package.swift                       # 已声明依赖与 testTarget
├── Sources/PluginFoo/
│   ├── FooPlugin.swift                 # 实现 QuickPlugin 的骨架
│   ├── Model/
│   ├── Service/
│   └── UI/
└── Tests/PluginFooTests/
    └── FooPluginTests.swift            # 非空测试 —— 避免 testTarget 空导致测试失败
```

**别忘的三步**：在 `AppCore.registerPlugins()` 注册、在 `project.yml` 加两处、
在 `docs/features.md` 写不变量。

---

## 7. 数据与文件位置

全部通过
[`AppPaths`](../Packages/QuickPlatform/Sources/QuickPlatform/System/AppPaths.swift)：

| 用途 | 位置 |
| --- | --- |
| 插件数据 | `~/Library/Application Support/<bundle id>/Plugins/<plugin id>/` |
| 缓存 | `~/Library/Caches/<bundle id>/` |
| 日志 | 统一日志系统（不是文件），见 [logging.md](logging.md) |

**Debug 与 Release 已隔离**：Debug 用 `com.ixxxxoooo.quick.dev`（产物 `Quick Dev.app`），
Release 用 `com.ixxxxoooo.quick`（产物 `Quick.app`）。各自独立的偏好、缓存、日志子系统与
TCC 授权。本地调试日志用 `./Scripts/logs.sh --dev`。

---

## 8. 发布

对齐 Jietu 的发布方案：稳定自签名 + DMG + 打 `v*` tag 触发 GitHub Release。

### 构建渠道

| | Debug | Release |
| --- | --- | --- |
| `PRODUCT_NAME` | `Quick Dev` | `Quick` |
| `PRODUCT_BUNDLE_IDENTIFIER` | `com.ixxxxoooo.quick.dev` | `com.ixxxxoooo.quick` |
| 产物 | `…/Debug/Quick Dev.app` | `…/Release/Quick.app` |

Debug 必须 `ENABLE_DEBUG_DYLIB = NO`（已写进 `project.yml`），否则主可执行只剩壳，
TCC 认不出稳定签名身份。

### 自签名（一次性）

TCC 按「bundle id + certificate leaf」认 App。ad-hoc 签名的设计要求是 `cdhash`，
**每构建一次就换身份**，升级后要重新授权。所以正式包必须用固定证书「Quick」。

```bash
# 1. 本机生成（已有「Quick」身份就跳过，千万别重跑）
bash Scripts/generate-signing-cert.sh

# 2. 导出并写入 GitHub Secrets
bash Scripts/export-signing-cert.sh --upload
# → QUICK_CERT_P12_BASE64 / QUICK_CERT_P12_PASSWORD
```

### 每次发版

```bash
# 本地验打包（可选）
bash Scripts/build-dmg.sh          # 产出 dist/Quick-<version>.dmg

# 打 tag 触发 .github/workflows/release.yml
git tag v1.0.0
git push origin v1.0.0
```

- 打 tag 的正式发布**没有证书就失败**；手动 `workflow_dispatch` 才允许
  `QUICK_ALLOW_ADHOC=1` 验流程（产物不适合发给用户）。
- **禁止**：重新跑 `generate-signing-cert.sh`、换 p12、改 Release 的 bundle id。
- 自签名未受系统信任：用户首次打开前需
  `xattr -dr com.apple.quarantine /Applications/Quick.app`
  （DMG 里的 `安装说明.txt` 有同款可复制命令）。

公证（Notarization）与 Developer ID 是后续可选升级；当前直接分发走自签名 + 解隔离。
