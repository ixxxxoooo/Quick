# 翻译（translator）

端上翻译 + 系统词典 + 系统朗读：输入文本给译文，输入单词给音标与释义，全部离线、
零第三方依赖。主面板里输入 `翻译 …` / `词典 …` 直接出结果，打开插件面板是完整的
输入 / 译文 / 词典工作台。

- 插件 id：`translator`
- 触发词：`翻译`、`translate`、`translation`、`词典`、`dict`、`dictionary`
- 内联前缀：`翻译 `/`tr `/`translate `/`fy `（翻译），`词典 `/`dict `/`dictionary `/`查词 `（查词）

---

## 不变量

1. **翻译走 Apple `Translation` 框架，端上完成、不联网。** 用
   `TranslationSession(installedSource:target:)` + `translate(_:)`。没有任何网络请求，
   也没有第三方翻译 API。
2. **`TranslationSession` 不是 `Sendable`。** 它只在 `TranslationService.perform`
   （`nonisolated static`）内部创建与使用，**不跨隔离域、不缓存** —— 放进 `@MainActor`
   类里再 `await` 它的方法会直接编译失败。框架自己复用底层资源。
3. **词典走 macOS `DictionaryServices`（`DCSCopyTextDefinition`），离线。** 系统装了
   哪些词典就用哪些（简体中文、牛津英汉等），不随包分发词库。
4. **语言探测与语言对取舍是纯逻辑。** `LanguageDetector`（按书写系统）与
   `LanguageResolution`（自动 / 目标 / 同语言回退 / 交换）不依赖 AppKit，可单测；
   `TranslationService` 用 `NLLanguageRecognizer` 探测后把结果交给它们取舍。
5. **词典解析是纯逻辑。** `DictionaryParser` 把系统词典返回的带标记文本
   （`|` 分词头/音标/释义、`▸` 分例句、`①②` 分义项）解析成结构化词条。
6. **内联结果与插件视图用一次性字段搭桥。** `TranslatorPlugin.pendingText`：
   `searchItems` 写、`TranslatorView` 出现时取走并清空 —— 主面板搜索与插件视图之间
   没有直接的上下文通道。
7. **历史是用户内容，存插件的键值存储（`PluginStorage`），不放 `UserDefaults`。**
   否则「重置设置」会连历史一起清掉。整体 JSON 存取，上限封顶，重复的「原文 + 语言对」去重。
8. **朗读用 `AVSpeechSynthesizer`，按语言选系统语音。** 不需要联网、不依赖词典音频。

## 内部结构

- `Model/TranslationLanguage.swift`：语言目录、`LanguageDetector`、`LanguageResolution`（纯逻辑）
- `Model/DictionaryEntry.swift`：`DictionaryEntry` / `DictionarySense` / `DictionaryParser`（纯逻辑）
- `Model/TranslatorQuery.swift`：`TranslatorIntent` + 触发词解析（纯逻辑）
- `Service/TranslationService.swift`：`Translation` 框架封装（视图入口 + 内联入口）
- `Service/DictionaryService.swift`：`DictionaryServices` 查询 + 缓存
- `Service/SpeechService.swift`：`AVSpeechSynthesizer` 朗读
- `Service/TranslationHistoryStore.swift`：历史读写
- `Service/PluginDefaults.swift`：目标语言偏好
- `UI/TranslatorView.swift`：输入 / 译文 / 词典三卡片 + 历史抽屉

## 持久化

| 键 | 位置 | 说明 |
| --- | --- | --- |
| `translator.targetLang` | `UserDefaults` | 默认目标语言（设置页） |
| `history` | `PluginStorage` | 最近 50 条翻译（原文 / 译文 / 语言对 / 时间） |

## 已知限制

- **语言包要先下载。** 端上翻译依赖系统已安装的语言包。语言对受支持但未下载时，
  面板会明确提示去「系统设置 › 通用 › 语言与地区 › 翻译语言」下载，而不是给一个假结果。
- **系统词典命中不保证。** 词典随系统安装情况而定；个别英文词会误命中中文条目
  （例如 `run` → 拼音 `rún` 的「瞤」），已在 `DictionaryService` 里按「纯拉丁查询 +
  CJK 词头」丢弃，交给翻译兜底。
- **没有「替换原文」按钮。** 面板可能出现在分离窗口里，此时无法确定该把译文粘回哪个应用，
  与其猜错不如只给「复制」。
