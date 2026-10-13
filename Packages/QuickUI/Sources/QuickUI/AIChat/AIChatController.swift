// AIChatController.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import Observation
import QuickCore
import QuickPlatform

/// AI 对话的状态与动作
///
/// 对话是**宿主级**功能（不是插件）：面板里输入后按 Tab 进入。控制器由 `AppCore` 持有，
/// 经 `PaletteDependencies` 交给协调器；视图只读它的状态、调它的动作。
///
/// 「流畅」的几条具体做法：
/// - 会话列表常驻内存，切换会话只是改 `currentID`，不读盘；
/// - 流式文本在内存里累积，每 ~40ms 才写进消息一次，避免每个 token 重排一次列表；
/// - 每个会话各有自己的生成任务，A 在生成时切到 B 继续聊，互不打断；
/// - 持久化是防抖的：先改内存、界面立刻响应，300ms 后在后台线程落盘；
/// - 删除先从界面消失，6 秒内可撤销，到期才真正删文件。
@MainActor
@Observable
public final class AIChatController {

    /// 对话在面板里占用的「模式 id」（与插件 id 同一命名空间，借用插件内容区的渲染路径）
    public static let modeID = "quick.ai-chat"

    /// 删除后允许撤销的时长
    public static let undoWindow: Duration = .seconds(6)
    /// 流式文本合并写入的最短间隔
    static let streamFlushInterval: Duration = .milliseconds(40)
    /// 落盘防抖
    static let saveDebounce: Duration = .milliseconds(300)

    static let systemPrompt =
        "你是 Quick 里的 AI 助手。回答简洁、准确；用户用什么语言提问就用什么语言回答；代码用 Markdown 代码块。"

    private static let log = QuickLog.logger("ai-chat")

    // MARK: - 状态

    public private(set) var sessions: [ChatSession] = []
    public private(set) var currentID: UUID?
    public private(set) var choices: [AIModelChoice] = []
    public private(set) var generatingIDs: Set<UUID> = []
    /// 刚被删除、还能撤销的会话
    public private(set) var pendingUndo: ChatSession?
    /// 刚被复制的消息（短暂亮起「已复制」）
    public private(set) var copiedID: UUID?

    /// 正在重命名的会话
    public var renamingID: UUID?
    public var sidebarFilter = ""
    public var isSidebarVisible: Bool {
        didSet { defaults.set(isSidebarVisible, forKey: SettingsKey.AI.chatSidebarVisible) }
    }

    /// 递增即「请把焦点给输入框 / 搜索框」；视图监听变化来抢焦点
    public private(set) var composerFocusToken = 0
    public private(set) var filterFocusToken = 0

    /// 每个会话各自的草稿：切走再切回来，没发出去的话还在
    private var drafts: [UUID: String] = [:]

    @ObservationIgnored private let store: ChatSessionFileStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let secrets: any SecretStoring
    @ObservationIgnored private var hasLoaded = false
    @ObservationIgnored private var generationTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var dirtyIDs: Set<UUID> = []
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private var undoTask: Task<Void, Never>?
    @ObservationIgnored private var copiedResetTask: Task<Void, Never>?
    @ObservationIgnored private var clearedSubscription: EventSubscription?

    public init(
        store: ChatSessionFileStore = ChatSessionFileStore(),
        defaults: UserDefaults = .standard,
        secrets: any SecretStoring = KeychainStore.shared,
        bus: EventBus = .shared
    ) {
        self.store = store
        self.defaults = defaults
        self.secrets = secrets
        self.isSidebarVisible =
            defaults.object(forKey: SettingsKey.AI.chatSidebarVisible) as? Bool ?? true
        clearedSubscription = bus.on(AIChatHistoryClearedEvent.self) { [weak self] _ in
            Task { @MainActor in self?.handleHistoryCleared() }
        }
    }

    // MARK: - 派生

    public var current: ChatSession? {
        currentID.flatMap { id in sessions.first { $0.id == id } }
    }

    public var isGeneratingCurrent: Bool {
        currentID.map { generatingIDs.contains($0) } ?? false
    }

    public var sections: [ChatSessionSection] {
        ChatSessions.sections(sessions.filter { !$0.isEmpty || $0.id == currentID }, query: sidebarFilter)
    }

    /// 侧栏从上到下的会话顺序（⌘[ / ⌘] 切换用）
    var visibleOrder: [UUID] {
        sections.flatMap { $0.sessions.map(\.id) }
    }

    /// 当前会话该用的模型；没有可用模型时为 nil（视图据此显示引导）
    public var currentChoice: AIModelChoice? {
        AIProviderStore.resolve(
            preferred: current?.model, default: AIProviderStore.defaultModel(from: defaults),
            choices: choices)
    }

    public var draft: String {
        get { currentID.flatMap { drafts[$0] } ?? "" }
        set {
            guard let id = currentID else { return }
            drafts[id] = newValue
        }
    }

    // MARK: - 进入 / 离开

    /// 进入对话：加载历史、刷新可选模型、保证有一个当前会话
    ///
    /// - Parameter seed: 从主搜索框带进来的文字，作为新会话的草稿（不自动发送——
    ///   用户按 Tab 是想「接着聊」，不一定想立刻发出去）
    public func enter(seed: String = "") {
        loadIfNeeded()
        refreshChoices()
        let trimmed = seed.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmed.isEmpty {
            // 带着内容进来：落到一个空会话里，草稿就是这段文字
            let target = reusableEmptySession() ?? insertNewSession()
            currentID = target
            drafts[target] = trimmed
        } else if current == nil {
            currentID = reusableEmptySession() ?? insertNewSession()
        }
        pruneEmptySessions(keeping: currentID)
        composerFocusToken += 1
        Self.log.notice("进入 AI 对话，会话数 \(self.sessions.count, privacy: .public)")
    }

    /// 把焦点还给输入框（面板重新唤出时）
    public func focusComposer() {
        composerFocusToken += 1
    }

    /// 离开对话：把没落盘的写掉
    ///
    /// **不停止生成**：用户退回主搜索只是暂时离开，回来时回复应该已经写完；
    /// 想中止要显式按停止或 Esc。
    public func leave() {
        renamingID = nil
        sidebarFilter = ""
        flushPendingSaves()
    }

    public func refreshChoices() {
        choices = AIProviderStore.loadChoices(defaults: defaults, secrets: secrets)
    }

    // MARK: - 会话操作

    /// 新建会话；当前已经是空会话时只把焦点放回输入框，不堆空会话
    public func newSession() {
        if let current, current.isEmpty {
            composerFocusToken += 1
            return
        }
        currentID = insertNewSession()
        pruneEmptySessions(keeping: currentID)
        composerFocusToken += 1
    }

    public func select(_ id: UUID) {
        guard sessions.contains(where: { $0.id == id }), id != currentID else {
            composerFocusToken += 1
            return
        }
        currentID = id
        renamingID = nil
        pruneEmptySessions(keeping: id)
        composerFocusToken += 1
    }

    /// ⌘[ / ⌘]：按侧栏顺序切到上一个 / 下一个
    public func selectAdjacent(_ offset: Int) {
        let order = visibleOrder
        guard !order.isEmpty else { return }
        guard let currentID, let index = order.firstIndex(of: currentID) else {
            select(order[0])
            return
        }
        let target = min(max(index + offset, 0), order.count - 1)
        select(order[target])
    }

    public func togglePin(_ id: UUID) {
        mutate(id, touch: false) { $0.isPinned.toggle() }
    }

    public func beginRename(_ id: UUID) {
        guard sessions.contains(where: { $0.id == id }) else { return }
        if !isSidebarVisible { isSidebarVisible = true }
        renamingID = id
    }

    /// 提交重命名；空标题恢复为自动标题
    public func commitRename(_ id: UUID, title: String) {
        defer { renamingID = nil; composerFocusToken += 1 }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        mutate(id, touch: false) { session in
            if trimmed.isEmpty {
                session.isTitleCustom = false
                let firstUser = session.messages.first { $0.role == .user }?.content ?? ""
                session.title = ChatSession.derivedTitle(from: firstUser)
            } else {
                session.title = trimmed
                session.isTitleCustom = true
            }
        }
    }

    /// 删除会话：立刻从界面消失，6 秒内可撤销
    public func delete(_ id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        let removed = sessions[index]
        let order = visibleOrder
        stop(id)

        // 上一次的撤销窗口还没过期就又删了一个：前一个此刻真正删除
        commitPendingDeletion()

        sessions.remove(at: index)
        drafts[id] = nil
        dirtyIDs.remove(id)
        if renamingID == id { renamingID = nil }

        if currentID == id {
            // 落到相邻的会话上（优先下一个，没有就上一个），连续删除时光标不会跳回顶部
            let position = order.firstIndex(of: id) ?? 0
            let remaining = order.filter { $0 != id }
            if remaining.isEmpty {
                currentID = nil
                currentID = insertNewSession()
            } else {
                currentID = remaining[min(position, remaining.count - 1)]
            }
        }

        // 空会话没必要给撤销
        guard !removed.isEmpty else {
            deleteFile(id)
            composerFocusToken += 1
            return
        }
        pendingUndo = removed
        undoTask?.cancel()
        undoTask = Task { [weak self] in
            try? await Task.sleep(for: Self.undoWindow)
            guard !Task.isCancelled else { return }
            self?.commitPendingDeletion()
        }
        composerFocusToken += 1
    }

    /// 撤销最近一次删除
    public func undoDelete() {
        guard let restored = pendingUndo else { return }
        undoTask?.cancel()
        pendingUndo = nil
        sessions.append(restored)
        currentID = restored.id
        composerFocusToken += 1
    }

    /// 撤销窗口到期（或被下一次删除顶掉）：真正删文件
    private func commitPendingDeletion() {
        guard let pending = pendingUndo else { return }
        undoTask?.cancel()
        pendingUndo = nil
        deleteFile(pending.id)
    }

    /// 清空全部历史（设置里的「清除对话历史」）
    private func handleHistoryCleared() {
        for id in Array(generationTasks.keys) { stop(id) }
        sessions.removeAll()
        drafts.removeAll()
        dirtyIDs.removeAll()
        pendingUndo = nil
        undoTask?.cancel()
        currentID = insertNewSession()
        Self.log.notice("AI 对话历史已清空")
    }

    // MARK: - 模型

    /// 给当前会话换模型（只影响之后的消息）
    public func setModel(_ ref: AIModelRef) {
        guard let id = currentID else { return }
        mutate(id, touch: false) { $0.model = ref }
        composerFocusToken += 1
    }

    // MARK: - 发送 / 停止 / 重新生成

    /// 发送输入框里的内容
    public func send() {
        guard let id = currentID else { return }
        send(draft, in: id)
    }

    func send(_ text: String, in id: UUID) {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, !generatingIDs.contains(id) else { return }

        if choices.isEmpty { refreshChoices() }
        guard let choice = resolvedChoice(for: id) else { return }

        mutate(id) { session in
            session.messages.append(ChatMessage(role: .user, content: content))
            if !session.isTitleCustom, session.messages.filter({ $0.role == .user }).count == 1 {
                session.title = ChatSession.derivedTitle(from: content)
            }
            session.model = choice.ref
        }
        drafts[id] = ""
        startGeneration(in: id, choice: choice)
    }

    /// 停止某个会话的生成；已生成的部分保留
    public func stop(_ id: UUID) {
        generationTasks[id]?.cancel()
    }

    /// 重新生成最后一条回复（失败重试也走这里）
    public func regenerate() {
        guard let id = currentID, !generatingIDs.contains(id) else { return }
        if choices.isEmpty { refreshChoices() }
        guard let choice = resolvedChoice(for: id) else { return }

        var hasUserMessage = false
        mutate(id, touch: false) { session in
            while session.messages.last?.role == .assistant { session.messages.removeLast() }
            hasUserMessage = session.messages.last?.role == .user
            if hasUserMessage { session.model = choice.ref }
        }
        guard hasUserMessage else { return }
        startGeneration(in: id, choice: choice)
    }

    /// 最后一条能复制的回复
    public var lastReplyID: UUID? {
        current?.messages.last { $0.role == .assistant && $0.failure == nil && !$0.content.isEmpty }?.id
    }

    /// 复制一条消息；`copiedID` 短暂亮起，视图据此把按钮换成「已复制」
    public func copy(messageID: UUID) {
        guard let text = current?.messages.first(where: { $0.id == messageID })?.content else { return }
        PasteboardService().copyText(text)
        copiedID = messageID
        copiedResetTask?.cancel()
        copiedResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(DesignTokens.Duration.copyFeedback))
            guard !Task.isCancelled else { return }
            self?.copiedID = nil
        }
    }

    private func resolvedChoice(for id: UUID) -> AIModelChoice? {
        let preferred = sessions.first { $0.id == id }?.model
        return AIProviderStore.resolve(
            preferred: preferred, default: AIProviderStore.defaultModel(from: defaults),
            choices: choices)
    }

    private func startGeneration(in id: UUID, choice: AIModelChoice) {
        guard let session = sessions.first(where: { $0.id == id }) else { return }
        let providers = AIProviderStore.loadProviders(from: defaults)
        guard let provider = providers.first(where: { $0.id == choice.ref.providerID }) else { return }

        let apiKey = AIProviderStore.apiKey(for: provider, secrets: secrets)
        let endpoint = provider.endpoint(model: choice.model, apiKey: apiKey)
        let options = AIConfig.load(from: defaults)
        let history = ChatSessions.contextMessages(session.messages).map {
            AIMessage(role: $0.role == .user ? .user : .assistant, content: $0.content)
        }
        let messages = [AIMessage.system(Self.systemPrompt)] + history

        let reply = ChatMessage(role: .assistant, content: "", model: choice.model)
        mutate(id) { $0.messages.append(reply) }
        generatingIDs.insert(id)
        Self.log.notice("AI 对话开始生成：\(choice.providerName, privacy: .public)")

        generationTasks[id] = Task { [weak self] in
            var buffer = ""
            var lastFlush = ContinuousClock.now
            var failure: String?
            do {
                for try await chunk in AIService.stream(
                    endpoint: endpoint, messages: messages, options: options)
                {
                    buffer += chunk
                    if lastFlush.duration(to: .now) >= Self.streamFlushInterval {
                        self?.appendReply(buffer, to: reply.id, in: id)
                        buffer = ""
                        lastFlush = .now
                    }
                }
            } catch {
                failure = error.localizedDescription
            }
            self?.appendReply(buffer, to: reply.id, in: id)
            self?.finishGeneration(id: id, replyID: reply.id, failure: failure)
        }
    }

    private func appendReply(_ text: String, to replyID: UUID, in id: UUID) {
        guard !text.isEmpty, let sIndex = sessions.firstIndex(where: { $0.id == id }),
            let mIndex = sessions[sIndex].messages.firstIndex(where: { $0.id == replyID })
        else { return }
        sessions[sIndex].messages[mIndex].content += text
    }

    private func finishGeneration(id: UUID, replyID: UUID, failure: String?) {
        generationTasks[id] = nil
        generatingIDs.remove(id)

        // 会话在生成途中被删了：什么都不用做
        guard sessions.contains(where: { $0.id == id }) else { return }
        mutate(id) { session in
            guard let index = session.messages.firstIndex(where: { $0.id == replyID }) else { return }
            if let failure {
                session.messages[index].failure = failure
            } else if session.messages[index].content.isEmpty {
                // 取消且一个字都没生成：不留空气泡
                session.messages.remove(at: index)
            }
        }
        if failure != nil { Self.log.error("AI 对话生成失败") }
        if id == currentID { composerFocusToken += 1 }
    }

    // MARK: - 快捷键

    /// 执行一个对话快捷键；返回是否已处理（false 时按键应交还给文本编辑）
    @discardableResult
    public func perform(_ shortcut: AIChatShortcut) -> Bool {
        switch shortcut {
        case .newChat:
            newSession()
        case .previousSession:
            selectAdjacent(-1)
        case .nextSession:
            selectAdjacent(1)
        case .deleteSession:
            // 输入框里有字时 ⌘⌫ 是「删到行首」，不能吞掉
            guard draft.isEmpty, let id = currentID else { return false }
            delete(id)
        case .toggleSidebar:
            isSidebarVisible.toggle()
            composerFocusToken += 1
        case .focusFilter:
            isSidebarVisible = true
            filterFocusToken += 1
        case .regenerate:
            regenerate()
        case .copyLastReply:
            guard let id = lastReplyID else { return false }
            copy(messageID: id)
        case .togglePin:
            guard let id = currentID else { return false }
            togglePin(id)
        case .renameSession:
            guard let id = currentID else { return false }
            beginRename(id)
        }
        return true
    }

    /// Esc 在对话里的优先级：取消重命名 → 停止生成 → （交给协调器）退出对话
    public func handleEscape() -> Bool {
        if renamingID != nil {
            renamingID = nil
            composerFocusToken += 1
            return true
        }
        if let id = currentID, generatingIDs.contains(id) {
            stop(id)
            return true
        }
        return false
    }

    // MARK: - 内部：会话增删

    @discardableResult
    private func insertNewSession() -> UUID {
        let session = ChatSession(model: AIProviderStore.defaultModel(from: defaults))
        sessions.append(session)
        return session.id
    }

    private func reusableEmptySession() -> UUID? {
        if let current, current.isEmpty { return current.id }
        return sessions.first { $0.isEmpty }?.id
    }

    /// 清掉除 `keeping` 以外的空会话：它们没有内容，不该留在列表和磁盘上
    private func pruneEmptySessions(keeping: UUID?) {
        sessions.removeAll { $0.isEmpty && $0.id != keeping && !generatingIDs.contains($0.id) }
    }

    /// 改一个会话；`touch` 为 true 时顺带刷新更新时间（侧栏据此重新排序）
    private func mutate(_ id: UUID, touch: Bool = true, _ change: (inout ChatSession) -> Void) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        change(&sessions[index])
        if touch { sessions[index].updatedAt = Date() }
        markDirty(id)
    }

    // MARK: - 持久化

    private func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        let store = self.store
        Task { [weak self] in
            let loaded = await Task.detached(priority: .userInitiated) { store.loadAll() }.value
            self?.merge(loaded)
        }
    }

    private func merge(_ loaded: [ChatSession]) {
        let existing = Set(sessions.map(\.id))
        sessions.append(
            contentsOf: loaded.filter { !existing.contains($0.id) && !$0.isEmpty }
                .map(ChatSessions.recoveringInterrupted))
        let evicted = ChatSessions.evictions(sessions)
        for id in evicted { deleteFile(id) }
        sessions.removeAll { evicted.contains($0.id) }
        Self.log.notice("AI 对话历史已加载：\(loaded.count, privacy: .public) 个会话")
    }

    private func markDirty(_ id: UUID) {
        dirtyIDs.insert(id)
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            while let self, !self.dirtyIDs.isEmpty {
                try? await Task.sleep(for: Self.saveDebounce)
                let snapshots = self.takeDirtySnapshots()
                let store = self.store
                await Task.detached(priority: .utility) {
                    for session in snapshots {
                        do { try store.save(session) } catch {
                            QuickLog.persistence.error(
                                "对话保存失败：\(error.localizedDescription, privacy: .public)")
                        }
                    }
                }.value
            }
            self?.flushTask = nil
        }
    }

    private func takeDirtySnapshots() -> [ChatSession] {
        let snapshots = dirtyIDs.compactMap { id in sessions.first { $0.id == id } }
            .filter { !$0.isEmpty }
        dirtyIDs.removeAll()
        return snapshots
    }

    /// 同步落盘：离开对话 / 退出应用时调用，防止防抖窗口内的改动丢失
    public func flushPendingSaves() {
        let snapshots = takeDirtySnapshots()
        for session in snapshots {
            do { try store.save(session) } catch {
                QuickLog.persistence.error("对话保存失败：\(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func deleteFile(_ id: UUID) {
        let store = self.store
        Task.detached(priority: .utility) { store.delete(id: id) }
    }
}
