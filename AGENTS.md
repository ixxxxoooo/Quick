# Quick

原生 macOS 效率启动器：菜单栏常驻 + 全局快捷键（默认 ⌥Space）唤出的命令面板，
聚合应用启动、剪贴板历史、计算器、文件搜索、系统控制等 17 个功能模块。

SwiftUI + AppKit，以 accessory 模式运行（`LSUIElement`，无 Dock 图标）。零第三方依赖。

视觉与面板尺寸参考 [Tinycast](https://github.com/) 的调色板：**750 × 475、圆角 26**。

---

## 技术立场：只面向最新，永远

**Quick 只支持一个 macOS 版本 —— 当前稳定版。** macOS 26+、Swift 6 语言模式。
没有兼容下限要守，没有 shim 层，没有废弃债 —— 这是本仓库能保持这么小的最主要原因。

写代码时就当平台是昨天发布的：

- **永远优先用现代 Apple API。** Observation 而不是 `ObservableObject`；Swift Concurrency
  而不是 `DispatchQueue` 或回调；`SMAppService` 而不是登录项 shim；结构化并发而不是游离的
  后台任务。
- **迁移，绝不包装。** 一个 API 有了现代替代品，就换掉调用点并删掉旧写法。保留旧拼写的
  包装层是本项目花最大力气在清理的东西。
- **被废弃的 API 是缺陷**，不是可以忍着的警告。
- **不引入兼容层、旧式 workaround、过时架构模式。** 要删就删，不要「标记为废弃」。
- **未经明确要求，绝不引入向下兼容。** 不要版本开关、不要迁移脚手架、不要「以防万一」的
  兜底分支。加这些需要一条明确的任务说「要加」。

下面两个是**有意的能力缺口依赖**，不是惯性，改动前先读理由：

- **Carbon（HIToolbox）注册全局快捷键。** 现代 API 里没有任何一个能注册系统级组合键，
  `RegisterEventHotKey` 至今仍是唯一的公开手段。见 `QuickPlatform/HotKey/HotKeyService.swift`。
- **入口用 AppKit 而非 SwiftUI `App`。** 在 macOS 26 上，只含 `MenuBarExtra` 的 SwiftUI App
  一旦显示窗口，就会进入 `makeMainMenu` 无限重建（CPU 打满）。因此 `@main` 是
  `NSApplication` + `AppDelegate`，菜单栏用 `NSStatusItem`，**全仓禁止 `MenuBarExtra`**。
  见 `Quick/QuickApp.swift`。

---

## 项目结构

| 目录 | 放什么 |
| --- | --- |
| `Quick/` | 应用目标（composition root）：`@main`、`AppDelegate`、`AppCore`、`StatusItemController` |
| `Packages/QuickCore/` | 内核：`QuickModule` 协议、`EventBus`、`SearchableItem`、`QuickLog`、字符串扩展 |
| `Packages/QuickUI/` | 共享 UI：`DesignTokens`、面板外壳（`PalettePanel`/`PaletteCoordinator`/`PaletteRootView`）、设计系统组件、`HUDController` |
| `Packages/QuickPlatform/` | 系统能力封装：热键、应用扫描、权限、剪贴板、图标缓存、路径 |
| `Packages/Module*/` | 17 个功能模块，每个一个包；大模块内部再分 `Model/` `Service/` `UI/` `Settings/` |
| `Scripts/` | 所有可执行脚本：测试、构建、lint、格式化、脚手架 |
| `docs/` | 规范文档（本目录）；每个功能模块的约束写在 `docs/features/` |
| `.githooks/` | 版本控制的 git 钩子，通过 `Scripts/setup.sh` 启用 |

**依赖方向是单向的，永不反向：**

```
Module*  →  QuickUI / QuickPlatform  →  QuickCore
   ↓                ↓                      ↓
   └────────────────┴──────────────────────┘
            只有 Quick/ 目标能同时看到模块
```

`QuickCore` 不认识任何模块，`QuickUI` / `QuickPlatform` 也不认识任何模块。只有 `Quick/AppCore.swift`
能 `import Module*`。

---

## 该先读哪份文档

| 在你……之前 | 读 |
| --- | --- |
| 改动任何接线、所有权、生命周期 | [docs/architecture.md](docs/architecture.md) |
| 写 Swift —— 命名、风格、并发、性能预算、注释 | [docs/standards.md](docs/standards.md) |
| 加日志、排查线上问题 | [docs/logging.md](docs/logging.md) |
| 声称一个改动「做完了」 | [docs/testing.md](docs/testing.md) |
| 编译、运行、调试、生成工程 | [docs/development.md](docs/development.md) |
| 新增或调整任何视图 | [docs/ui.md](docs/ui.md) |
| 动某个模块的内部 | [docs/features/](docs/features/) —— 每份以不变量开头 |

---

## 不可协商的红线

没有一条明确的任务要求，就不要打破它们。功能专有的约束写在各自 feature 文档的
`## 不变量` 小节里。

- **`AppCore` 是唯一的所有者。** 新的长生命周期状态挂到 `AppCore` 上，在 `start()` 里接线，
  **绝不**另起一个并行的单例。视图通过 `@Environment` 拿协调器，不直接拿 `AppCore`。
- **模块只在 `AppCore.registerModules()` 里实例化。** 这是全仓唯一 `modules.append(...)` 的地方。
  模块**不自注册**，没有插件扫描，没有服务定位器。
- **模块之间只通过 `EventBus` 通信。** 模块互不 `import`、互不持有引用、互不直接调用。
  需要通知别人就 `EventBus.shared.post(...)`；需要被通知就 `on(...)` 并保存
  `EventSubscription`（不保存会随返回值一起销毁）。
- **`QuickModule` 是 `@MainActor` 的。** 模块状态默认主线程隔离；跨 actor 传递的模型类型必须
  `Sendable`。重活、IO 密集的活放到 `nonisolated` 函数里，由 `Task.detached` 驱动，
  **不要新增第二个 actor**。
- **Swift 6 语言模式：数据竞争是硬错误。** 严格并发是 `complete`。引入一个新的共享可变状态前，
  先想清楚它归哪个 actor。
- **`Model/` 下的文件不允许 `import AppKit` 或 `import SwiftUI`。** 环境事实（时钟、文件系统、
  家目录、利率）一律作为参数注入 —— 这样模型层才能被测试独立编译。这条由编译期保证，不靠约定。
- **UI 数值只来自 `DesignTokens`。** 视图里出现裸的间距、圆角、尺寸、颜色字面量就是缺陷。
  见 [docs/ui.md](docs/ui.md)。
- **日志只走 `QuickLog`，禁止裸 `print`。** 每个模块用自己的 category。见
  [docs/logging.md](docs/logging.md)。
- **裸 `try!` 永远不可接受。** 强制转换偶尔有正当理由（AppKit / AX 桥接），所以只警告。
- **`project.yml` 是工程的唯一真相。** `Quick.xcodeproj` 由 XcodeGen 生成但**要提交** ——
  打开工程不该依赖本机是否装了 xcodegen。改完 `project.yml` 必须跑 `xcodegen generate`
  并把两边一起提交。禁止手工编辑 `project.pbxproj`。
- **不要新增第三方依赖。** 需要新能力时，先确认系统框架做不到。

---

## 开发流程

### 日常改动

```bash
./Scripts/setup.sh                 # 首次克隆后执行一次：启用 git 钩子
./Scripts/format.sh                # 改完先格式化
./Scripts/run-tests.sh             # 跑全量测试（提交前必跑）
./Scripts/build.sh                 # 构建 .app
./Scripts/lint.sh                  # 排版 + 语义检查
```

提交时 `pre-commit` 钩子会自动再跑一遍，失败即拒绝提交。见
[docs/development.md#提交](docs/development.md)。

### 新增一个功能模块

1. 生成骨架：`./Scripts/new-module.sh ModuleFoo`（同时建好 `Package.swift`、模块类、
   `Model/ Service/ UI/ Settings/` 目录与一个占位测试）。
2. 实现 `ModuleFooModule.swift`，遵循 `QuickModule`。`static var id` 必须全局唯一 ——
   它是事件路由和设置存储的主键，一旦发布就不能再改。
3. 在 `Quick/AppCore.swift#registerModules()` 里注册。**这是唯一实例化模块的地方。**
4. 在 `project.yml` 里加两处（`packages:` 与 `Quick` target 的 `dependencies:`），
   然后 `xcodegen generate`。
5. 加测试，`./Scripts/run-tests.sh` 必须全绿。
6. 加日志：`QuickLog.module("<id>")`，覆盖 `activate()` / `deactivate()` / 错误路径。
7. 在 `docs/features/<id>.md` 写下这个模块的不变量。
8. 提交。

### 定义「做完」

每一项都不可跳过；细节见 [docs/testing.md](docs/testing.md)。

- `./Scripts/run-tests.sh` 全绿 —— **这是提交的硬门禁**。
- `./Scripts/build.sh` 通过，且**没有新增警告**（当前基线是 0 个新警告）。
- `./Scripts/lint.sh` 干净。
- App 实际启动过，面板能被快捷键唤出，Esc 能关闭，CPU 空闲时接近 0。
- `grep -rln 'import AppKit\|import SwiftUI\|import Cocoa' Packages/*/Sources/*/Model/` 无输出。
- 该改的文档在**同一个提交**里改掉了。

---

## 提交规范

**提交信息一律使用英文。** 这是硬性要求 —— 提交历史要能被任何人、任何工具读懂。

格式遵循 [Conventional Commits](https://www.conventionalcommits.org/)：

```
<type>(<scope>): <祈使语气的小写英文描述>

<可选正文：为什么这么改，而不是改了什么>

<可选页脚：Refs #123 / BREAKING CHANGE: ...>
```

- **type**：`feat` `fix` `refactor` `perf` `docs` `test` `chore` `build` `ci` `style` `revert`
- **scope**：模块 id 或区域，如 `launcher` `palette` `quickui` `core` `hotkey` `tooling` `docs`
- 主题行祈使语气、小写开头、**句末不加句号**、不超过 72 字符。
- 正文写**为什么**，不写「改了什么」—— 改动本身 `git diff` 已经说了。

```
feat(clipboard): add pinning with a 30-entry history cap
fix(palette): keep the panel on screen when the app deactivates
perf(launcher): score app names once per refresh instead of per keystroke
docs(standards): state the logging contract for modules
```

`commit-msg` 钩子会校验格式并拒绝非 ASCII 主题行（等价于强制英文）。

**每次提交前必须跑完测试。** `pre-commit` 钩子会强制执行，不要用 `--no-verify` 绕过；
万一绕过了，在推送前补跑一次。
