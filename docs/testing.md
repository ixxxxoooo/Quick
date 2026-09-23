# 测试

**测试是提交的硬门禁。** 每次提交前 `./Scripts/run-tests.sh` 必须全绿，
`pre-commit` 钩子会强制执行。

---

## 1. 框架：Swift Testing

统一使用 [Swift Testing](https://developer.apple.com/documentation/testing)
（`import Testing`），不用 XCTest —— 新代码里出现 `import XCTest` 或 `func testXxx()`
就是不符合规范。

```swift
import Testing
@testable import PluginCalculator

@Suite("计算器引擎")
struct CalcEngineTests {

    @Test("四则运算")
    func arithmetic() {
        #expect(CalcEngine.evaluate("1+2*3")?.display == "7")
    }

    @Test("非法表达式")
    func invalidExpression() {
        #expect(CalcEngine.evaluate("1++") == nil)
    }
}
```

- `@Suite("中文描述")` 标在 `struct` 上，描述用中文（和注释一致）。
- `@Test("中文描述")` 标在每个用例上，一个用例只断言一件事。
- `#expect(...)` 优于 `#require(...)`；只有「后面所有断言都依赖这个前置条件」时才用
  `#require`。
- 需要主 actor 的用 `@MainActor @Suite` / `@MainActor @Test`，不要用
  `await MainActor.run { }` 包断言。

---

## 2. 测试放在哪

**测试跟着包走**，不是集中在根目录的 `Tests/`：

```
Packages/<Package>/Tests/<Package>Tests/<Something>Tests.swift
```

单元测试必须能脱离 App 目标独立跑通 —— 这正是模型层禁止 `import SwiftUI`/`AppKit`
的原因（见 [standards.md](standards.md)）。

### 当前测试分布

| 包 | 测试文件 | 状态 |
| --- | --- | --- |
| `QuickCore` | `EventBus`、模糊匹配与拼音匹配、SQLite 封装、`PluginStorage`、设置键、最近使用 | 有覆盖 |
| `QuickUI` | 面板显隐与模式、分离窗口控制器、悬浮胶囊几何与位置持久化、面板自动行为与设置读取、首屏按最近使用重排 | 有覆盖 |
| `QuickPlatform` | 热键注册、应用扫描与条目的匹配形态、键盘布局服务 | 有覆盖 |
| `PluginLauncher` | 使用频率与收藏的持久化往返 | 有覆盖 |
| `PluginClipboard` | 去重/排序/剪枝、条数与图片预算、坏行降级 | 有覆盖 |
| `PluginNotes` · `PluginSnippets` | 表读写往返、排序 | 有覆盖 |
| `PluginSystemMonitor` | 时长/字节/`ps` 解析、内存/磁盘/电源/CPU tick、温度聚合、偏好映射 | 有覆盖 |
| `PluginKillProcess` | `ps` 解析与过滤、偏好回落、触发词入口 | 有覆盖 |
| `PluginScreenshot` | `screencapture` 参数、文件名与时间戳格式 | 有覆盖 |
| `PluginTranslator` | 词典方向、触发词前缀、语言判定 | 有覆盖 |
| `PluginOCR` · `PluginFileSearch` | 触发词匹配、文本拼接、查询前缀解析、图标映射 | 有覆盖 |
| `PluginCalendar` | 时间区间格式、排序、农历文本 | 有覆盖 |
| `PluginAI` | Provider 注册表完整性、搜索排序与触发闸门 | 有覆盖 |
| 11 个开发者工具 | 各自的纯逻辑（编解码、格式化、diff、字数统计…） | 有覆盖 |
| 其余插件 | 插件契约 + 从服务里抽出来的纯逻辑 | 有覆盖 |

**29 个包全部有测试目标，由 `Scripts/run-tests.sh` 强制**：少一个包就红。
规则是「每个包都要有测试」而不是「想测才测」—— 系统依赖重不等于没有可测的东西，
见下面一节。

**注意：声明了 testTarget 却没有测试文件，会让 `swift test` 直接失败**
（`error: no tests found`）。所以「加测试」和「声明目标」必须同时发生，
不能先声明后补。给插件加 testTarget 时，同一个提交里必须有至少一个非空测试文件。

### 系统依赖的部分怎么测

EventKit、Vision、Spotlight、CoreLocation、Accessibility、`screencapture` 这类东西在测试里
要么要授权、要么很慢、要么直接挂。规矩是：**把系统调用挤到边缘，把纯计算剥出来测**。

- 窗口布局的坐标计算、`ps` 输出的解析、`resolv.conf` 的解析、`screencapture` 的参数拼装、
  天气授权状态的映射 —— 这些都是这样从系统调用里剥出来的，
  落在 `Sources/<Pkg>/Model/`（Foundation-only，可脱离 App 独立编译）。
- 真正的系统调用不测；测的是**我们对返回值的处理**。
- 剥不出来（例如「向 EventKit 取事件」这一步本身）就明确写进报告，
  不要为了凑覆盖率写一个永远为真的测试。

---

## 3. 该测什么

按优先级从高到低。**优先测纯逻辑** —— 它们最容易测、最不容易误报、价值最高。

**必测（纯逻辑层）**
- 解析、匹配、评分：模糊匹配、计算器表达式、模板变量替换、文本 diff。
- 持久化：`Store` 的读写往返、损坏数据时的降级、上限裁剪（例如历史只留 N 条）。
- 状态机：面板显隐与模式切换、插件启停的幂等性。
- `EventBus`：订阅/取消订阅/`removeAll` 的语义。

**应测（契约层）**
- 每个 `QuickPlugin`：`searchItems` 对空查询与正常查询的行为、
  `id` 的唯一性、`deactivate()` 是否落盘。
- 关键不变量：`hidesOnDeactivate == false`、面板尺寸有效、
  `SearchableItem.id` 在同一插件内不重复。

**不测（除非另有理由）**
- SwiftUI 视图的像素级外观 —— 那靠人工验收与 `docs/ui.md` 的规范约束。
- 私有方法的实现细节 —— 测公开行为。
- 系统 API 的封装本身（`NSWorkspace` 会不会返回图标不是我们的责任）；
  测的是**我们对返回值的处理**。

**UI / 面板至少覆盖**（这是本项目已有的约定）：显隐状态、快捷键注册结果、
关键路径不崩溃。

---

## 4. 测试纪律

- **不要为了通过测试而改测试的期望值。** 先判断是代码错了还是期望错了。
- **测试必须可重复。** 不依赖真实剪贴板内容、不依赖网络、不依赖用户机器上装了什么应用。
  需要外部输入就注入：把路径、时钟、数据源做成参数。
- **不要依赖执行顺序。** 每个用例自己准备状态、自己清理。
- **测试里不要 `try!` 或 `fatalError`** —— 用 `#require` 表达前置条件。
- **用例名与断言消息写清楚失败时说明了什么。** `#expect(results.count == 3, "前缀匹配应命中 3 条")`
  比裸断言强得多。
- **新增功能必须带测试**（AGENTS.md 的红线）。「只改代码不写测试然后说做完了」
  在本项目里是不允许的。

---

## 5. 怎么跑

```bash
./Scripts/run-tests.sh                    # 全部包
./Scripts/run-tests.sh QuickCore          # 单个包
./Scripts/run-tests.sh PluginCalculator QuickCore   # 多个包
```

脚本会对每个声明了测试的包执行 `swift test`，汇总结果，**任何一个包失败就整体退出非零**
—— 这正是 `pre-commit` 钩子依赖的信号。

底层等价于：

```bash
swift test --package-path Packages/QuickCore
```

---

## 6. 手工验收（自动化测试覆盖不到的部分）

单元测试不能证明「app 真的能用」。声称完成前，在 App 层面手工过一遍：

```bash
./Scripts/build.sh --run     # 构建并启动
```

逐项确认：

1. **进程存活**：启动后没有立刻退出，没有崩溃报告。
2. **CPU 正常**：面板显示后 CPU 接近空闲。**持续 > 20% 就是 bug**
   （历史故障：`@Observable` 引起的 AttributeGraph 死循环）。
3. **唤醒**：⌥Space 能唤出面板；菜单栏图标的「显示 Quick」也能。
4. **窗口真的可见**：用 `CGWindowListCopyWindowInfo` 或肉眼确认面板出现且尺寸正常
   —— 不要只看 `isVisible == true`，那不能证明窗口在屏幕上。
5. **冒烟**：搜索框能输入、上下键能选、回车能执行、Esc 先清空搜索框、再按一次关闭面板。
6. **焦点归还**：关闭面板后，之前的前台应用重新获得焦点。

### 自检手段

- **启动参数 `-showPalette`**：启动后立即显示面板，省掉手按快捷键。
- **分布式通知**：应用内用 `DistributedNotificationCenter` 监听
  `com.ixxxxoooo.quick.togglePalette` 来切换面板。**不要用 `notifyutil -p`** ——
  那是另一套 notify API，不互通。
- **窗口可见性**：`CGWindowListCopyWindowInfo` 确认存在名为 `Quick` 的窗口且尺寸正常。
- **日志**：`./Scripts/logs.sh` 实时跟踪，看面板显隐耗时与搜索耗时是否在预算内。

---

## 7. 性能回归

性能预算见 [standards.md#性能预算](standards.md)。以下改动必须在提交信息里附上改前改后的
测量数据，否则视为未验证：

- 改动搜索路径（模糊匹配、排序、聚合）。
- 改动应用扫描或文件索引。
- 改动面板显隐路径。
- 引入新的缓存或并发。

测量方式：`./Scripts/logs.sh` 看 signpost 输出的耗时，或用 Instruments 的
Points of Interest 轨道。
