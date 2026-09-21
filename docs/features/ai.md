# AI 聚合（ai）

把 8 个 AI 官网（DeepSeek / ChatGPT / Gemini / Claude / 豆包 / Kimi / 智谱 / 通义千问）
聚合成一个插件：在搜索结果里直达，或在 Quick 自己的窗口里打开页面。

## 不变量

- **窗口是普通窗口，不是非激活面板。** 这一条决定「切走之后还能不能找回来」：非激活面板
  不进 ⌘Tab / Mission Control，用户一旦从 AI 窗口切到别的应用，就只剩「再从面板点一次」
  这一条路。所以 `AIWebViewPanel` 的 styleMask **不含** `.nonactivatingPanel`，并且
  `canBecomeMain` 为真。改动这一条之前先读 `docs/architecture.md` 的「AI 网页窗口」一节。
- **可见窗口占用 Dock 身份，隐藏即交还。** accessory 应用不在 ⌘Tab 里，所以只要有可见的
  AI 窗口，就通过 `ActivationPolicyKeeper` 暂时变成 `.regular`；最后一个窗口隐藏或销毁时
  交还。**隐藏（点红绿灯）也要交还**：窗口看不见时没有「找回来」的需求，Dock 里挂一个
  点开什么都没有的图标只会更困惑。记账走持有者集合，不能改成计数器 —— 设置窗口也会登记。
- **唤起时到最前要三句一起写**：`NSApp.activate(ignoringOtherApps:)` +
  `makeKeyAndOrderFront` + `orderFrontRegardless`。少一句就会「唤醒了却不在最前面」，
  新建的窗口尤其容易 —— 它本来就是被 `makeKeyAndOrderFront` 排在最后才显示的。
- **关闭只是隐藏，销毁是显式命令。** `AIWebViewPanel.close()` 走 `onClose` → `orderOut`，
  这样登录态与会话历史留着；只有面板上的「关闭」才真正 `destroyWindow`。
  `destroyWindow` / `closeAll` 会先清掉 `onClose` 再 `close()` —— 否则关不掉。
- **窗口标识是 `quick.ai.<providerId>`。** 测试与窗口排查都按它找窗口，不要改格式。
- **胶囊是窗口里唯一常驻的控件，且只属于 AI 窗口。** 内容是一整块第三方网页，
  不能依赖页面 DOM（随时会变），所以控制只能浮在上面；分离窗口有自己的标题栏，
  控制长在标题栏里，不用胶囊（见 `docs/architecture.md`）。
- **Provider 关键词表是匹配的唯一事实来源。** `AIProviderRegistry.all` 里每个 Provider 的
  `keywords` 同时用于触发词闸门与打分，不要在别处再抄一份。
- **闸门认前缀，但要求查询词至少 3 个字符。** Provider 名是「打一半就该收窄」的东西：
  `deep` 要能出 DeepSeek、`chatgp` 要能出 ChatGPT。整词规则（`String.matchesAnyTrigger`，
  用来挡住 `email`→`ai` 那类误命中）做不到这件事，所以闸门用的是
  `matchesAnyTriggerIncludingPrefix` —— 它先走整词判定，再额外放行「触发词以查询词开头」。
  **长度下限不能去掉**：没有它，打一个字母就会命中一片（`a`→`ai`、`d`→`deepseek`）。
  注意前缀只放宽「开头」：`seek` 是 `deepseek` 的中间片段，仍然搜不到。
- **命中之后按已有的模糊打分排。** 闸门只决定「要不要搜」，相关度仍由
  `word.fuzzyScore(keyword)` 给（前缀 0.9）再乘 0.8 —— 所以 `deep` 命中的 DeepSeek
  relevance 是 0.72，排在门户入口（0.6）之前。

## 内部结构

| 类型 | 职责 |
| --- | --- |
| `AIPlugin` | 插件入口：搜索结果（门户入口 + 命中的 Provider）与 `makeView()` |
| `AIProvider` / `AIProviderRegistry` | Provider 元数据与注册表（名称、URL、图标、强调色、关键词） |
| `AIWebViewWindowManager` | 每个 Provider 一个 WebView 窗口，生命周期与 Dock 身份 |
| `AIWebViewPanel` | 自定义 NSPanel：点红绿灯只隐藏不销毁 |
| `AIPortalView` | 插件视图：卡片列表，显示每个 Provider 的「运行中 / 就绪」与打开/刷新/关闭 |

`AIWebViewWindowManager` 由 `AIPlugin` 持有而**不是单例**：窗口是插件的一部分，
插件停用时窗口应当一起收掉（`AIPlugin.deactivate()` → `closeAll()`）。

## 窗口与页面的关系

- 页面跑在 `WKWebView` 里，用 Chrome 的 UA 串 —— 这些官网普遍会拦非浏览器 UA。
- 数据存储用 `WKWebsiteDataStore.default()`，所以登录态在 Quick 重启后仍然在。
- 窗口关闭只 `orderOut`：重建一个 WKWebView 会丢掉登录态，代价远高于留一个隐藏窗口。
