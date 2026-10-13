// AIChatControllerTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore
import QuickPlatform
import Testing

@testable import QuickUI

/// 控制器的状态机测试
///
/// 不碰网络：服务商的 Base URL 用非本机 `http://`，`AIService` 在构造请求时就会拒绝，
/// 于是「发送 → 生成 → 失败」整条路径同步可测。
@MainActor
private struct Fixture {
    let controller: AIChatController
    let store: ChatSessionFileStore
    let defaults: UserDefaults
    let bus = EventBus()

    init(withProvider: Bool = true, preload: [ChatSession] = []) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AIChatControllerTests-\(UUID().uuidString)", isDirectory: true)
        store = ChatSessionFileStore(directory: directory)
        for session in preload { try store.save(session) }

        defaults = UserDefaults(suiteName: "AIChatControllerTests-\(UUID().uuidString)")!
        let secrets = InMemorySecretStore()
        if withProvider {
            let provider = AIProvider(
                id: "p1", name: "测试", baseURL: "http://insecure.example.com", models: ["m1", "m2"])
            AIProviderStore.saveProviders([provider], to: defaults)
            try AIProviderStore.setAPIKey("k", for: provider, secrets: secrets)
        }
        controller = AIChatController(
            store: store, defaults: defaults, secrets: secrets, bus: bus)
    }

    /// 等当前会话的生成结束（最多约 2 秒）
    func settle() async {
        for _ in 0..<200 where !controller.generatingIDs.isEmpty {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    /// 在当前会话里发一条消息并等它结束
    func chat(_ text: String) async {
        controller.draft = text
        controller.send()
        await settle()
    }
}

@MainActor
@Suite("AIChatController 会话状态机")
struct AIChatControllerTests {

    @Test("进入时保证有一个空的当前会话")
    func enterCreatesBlankSession() throws {
        let fx = try Fixture()
        fx.controller.enter()
        #expect(fx.controller.current?.isEmpty == true)
        #expect(fx.controller.sessions.count == 1)
    }

    @Test("带文字进入：文字成为草稿，不会自动发送也不会堆出多个空会话")
    func enterWithSeed() throws {
        let fx = try Fixture()
        fx.controller.enter()
        fx.controller.enter(seed: "  你好  ")
        #expect(fx.controller.draft == "你好")
        #expect(fx.controller.current?.isEmpty == true)
        #expect(fx.controller.sessions.count == 1)
    }

    @Test("当前已是空会话时新建只是回到输入框")
    func newSessionReusesBlank() throws {
        let fx = try Fixture()
        fx.controller.enter()
        let before = fx.controller.composerFocusToken
        fx.controller.newSession()
        #expect(fx.controller.sessions.count == 1)
        #expect(fx.controller.composerFocusToken > before)
    }

    @Test("没有可用模型时发送无效")
    func sendWithoutModel() throws {
        let fx = try Fixture(withProvider: false)
        fx.controller.enter()
        fx.controller.draft = "你好"
        fx.controller.send()
        #expect(fx.controller.current?.messages.isEmpty == true)
        #expect(fx.controller.draft == "你好")
    }

    @Test("发送：写入用户消息、推出标题、失败信息挂在助手消息上")
    func sendFailsGracefully() async throws {
        let fx = try Fixture()
        fx.controller.enter()
        await fx.chat("今天天气怎么样\n第二行")

        let session = try #require(fx.controller.current)
        #expect(session.title == "今天天气怎么样")
        #expect(session.messages.count == 2)
        #expect(session.messages[0].role == .user)
        #expect(session.messages[1].role == .assistant)
        #expect(session.messages[1].failure != nil)
        #expect(session.model == AIModelRef(providerID: "p1", model: "m1"))
        #expect(fx.controller.draft.isEmpty)
        #expect(fx.controller.generatingIDs.isEmpty)
    }

    @Test("空白消息不发送")
    func blankMessageIgnored() async throws {
        let fx = try Fixture()
        fx.controller.enter()
        await fx.chat("   \n ")
        #expect(fx.controller.current?.isEmpty == true)
    }

    @Test("重新生成：替换末尾的失败回复，不会越叠越多")
    func regenerateReplacesTail() async throws {
        let fx = try Fixture()
        fx.controller.enter()
        await fx.chat("问")
        fx.controller.regenerate()
        await fx.settle()
        let messages = try #require(fx.controller.current?.messages)
        #expect(messages.count == 2)
        #expect(messages.map(\.role) == [.user, .assistant])
    }

    @Test("切换模型只改当前会话")
    func setModel() async throws {
        let fx = try Fixture()
        fx.controller.enter()
        fx.controller.setModel(AIModelRef(providerID: "p1", model: "m2"))
        #expect(fx.controller.currentChoice?.model == "m2")
    }

    @Test("切走时清掉没有内容的空会话")
    func prunesEmptySessions() async throws {
        let fx = try Fixture()
        fx.controller.enter()
        await fx.chat("第一个")
        fx.controller.newSession()
        let blank = try #require(fx.controller.currentID)
        let first = try #require(fx.controller.sessions.first { $0.id != blank }?.id)
        fx.controller.select(first)
        #expect(fx.controller.sessions.count == 1)
        #expect(fx.controller.currentID == first)
    }

    @Test("删除当前会话落到相邻会话，并可撤销")
    func deleteAndUndo() async throws {
        let fx = try Fixture()
        fx.controller.enter()
        await fx.chat("甲")
        fx.controller.newSession()
        await fx.chat("乙")
        fx.controller.newSession()
        await fx.chat("丙")
        #expect(fx.controller.sessions.count == 3)

        let order = fx.controller.visibleOrder
        let middle = order[1]
        fx.controller.select(middle)
        fx.controller.delete(middle)
        #expect(fx.controller.sessions.count == 2)
        // 删除后落到原位置的下一个
        #expect(fx.controller.currentID == order[2])
        #expect(fx.controller.pendingUndo?.id == middle)

        fx.controller.undoDelete()
        #expect(fx.controller.sessions.count == 3)
        #expect(fx.controller.currentID == middle)
        #expect(fx.controller.pendingUndo == nil)
    }

    @Test("删光所有会话后自动给一个空会话")
    func deleteLastLeavesBlank() async throws {
        let fx = try Fixture()
        fx.controller.enter()
        await fx.chat("唯一")
        let id = try #require(fx.controller.currentID)
        fx.controller.delete(id)
        #expect(fx.controller.sessions.count == 1)
        #expect(fx.controller.current?.isEmpty == true)
    }

    @Test("重命名：自定义标题不会被后续消息覆盖，空标题恢复自动标题")
    func rename() async throws {
        let fx = try Fixture()
        fx.controller.enter()
        await fx.chat("原始问题")
        let id = try #require(fx.controller.currentID)

        fx.controller.beginRename(id)
        #expect(fx.controller.renamingID == id)
        fx.controller.commitRename(id, title: "  我的标题  ")
        #expect(fx.controller.renamingID == nil)
        #expect(fx.controller.current?.title == "我的标题")

        await fx.chat("第二个问题")
        #expect(fx.controller.current?.title == "我的标题")

        fx.controller.commitRename(id, title: "")
        #expect(fx.controller.current?.title == "原始问题")
        #expect(fx.controller.current?.isTitleCustom == false)
    }

    @Test("置顶的会话排在「置顶」分组")
    func pinning() async throws {
        let fx = try Fixture()
        fx.controller.enter()
        await fx.chat("甲")
        fx.controller.newSession()
        await fx.chat("乙")
        let first = try #require(fx.controller.sessions.first { $0.title == "甲" }?.id)
        fx.controller.togglePin(first)
        #expect(fx.controller.sections.first?.id == "pinned")
        #expect(fx.controller.sections.first?.sessions.first?.id == first)
    }

    @Test("侧栏搜索按标题与正文过滤")
    func filtering() async throws {
        let fx = try Fixture()
        fx.controller.enter()
        await fx.chat("苹果")
        fx.controller.newSession()
        await fx.chat("香蕉")
        fx.controller.sidebarFilter = "香"
        #expect(fx.controller.visibleOrder.count == 1)
        fx.controller.sidebarFilter = "不存在"
        #expect(fx.controller.visibleOrder.isEmpty)
    }

    @Test("⌘[ ⌘] 按侧栏顺序切换并在两端停住")
    func adjacentSelection() async throws {
        let fx = try Fixture()
        fx.controller.enter()
        await fx.chat("甲")
        fx.controller.newSession()
        await fx.chat("乙")
        let order = fx.controller.visibleOrder
        fx.controller.select(order[0])
        fx.controller.selectAdjacent(-1)
        #expect(fx.controller.currentID == order[0])
        fx.controller.selectAdjacent(1)
        #expect(fx.controller.currentID == order[1])
        fx.controller.selectAdjacent(1)
        #expect(fx.controller.currentID == order[1])
    }

    @Test("每个会话有自己的草稿")
    func perSessionDrafts() async throws {
        let fx = try Fixture()
        fx.controller.enter()
        await fx.chat("甲")
        let first = try #require(fx.controller.currentID)
        fx.controller.draft = "没发出去的话"
        fx.controller.newSession()
        #expect(fx.controller.draft.isEmpty)
        fx.controller.select(first)
        #expect(fx.controller.draft == "没发出去的话")
    }

    @Test("Esc：先取消重命名，没有可取消的就交还协调器")
    func escapePriority() async throws {
        let fx = try Fixture()
        fx.controller.enter()
        await fx.chat("甲")
        let id = try #require(fx.controller.currentID)
        fx.controller.beginRename(id)
        #expect(fx.controller.handleEscape())
        #expect(fx.controller.renamingID == nil)
        #expect(fx.controller.handleEscape() == false)
    }

    @Test("输入框有字时 ⌘⌫ 不吞键，空时才删除会话")
    func deleteShortcutYieldsToTextEditing() async throws {
        let fx = try Fixture()
        fx.controller.enter()
        await fx.chat("甲")
        fx.controller.draft = "半句话"
        #expect(fx.controller.perform(.deleteSession) == false)
        #expect(fx.controller.sessions.count == 1)

        fx.controller.draft = ""
        #expect(fx.controller.perform(.deleteSession))
        #expect(fx.controller.pendingUndo != nil)
    }

    @Test("会话落盘并能在新控制器里加载；被中断的回复标成失败")
    func persistenceRoundTrip() async throws {
        let fx = try Fixture()
        fx.controller.enter()
        await fx.chat("要保存的问题")
        fx.controller.flushPendingSaves()
        let saved = fx.store.loadAll()
        #expect(saved.count == 1)
        #expect(saved.first?.title == "要保存的问题")

        let interrupted = ChatSession(
            title: "被中断", messages: [
                ChatMessage(role: .user, content: "问"),
                ChatMessage(role: .assistant, content: "")
            ])
        let second = try Fixture(preload: [interrupted])
        second.controller.enter()
        for _ in 0..<200 where second.controller.sessions.count < 2 {
            try? await Task.sleep(for: .milliseconds(10))
        }
        let loaded = try #require(second.controller.sessions.first { $0.title == "被中断" })
        #expect(loaded.messages[1].failure == "上次生成被中断")
    }

    @Test("清空历史事件：会话重置为一个空会话")
    func historyCleared() async throws {
        let fx = try Fixture()
        fx.controller.enter()
        await fx.chat("甲")
        fx.bus.post(AIChatHistoryClearedEvent())
        await Task.yield()
        for _ in 0..<50 where fx.controller.sessions.count != 1 || fx.controller.current?.isEmpty != true {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(fx.controller.sessions.count == 1)
        #expect(fx.controller.current?.isEmpty == true)
    }
}
