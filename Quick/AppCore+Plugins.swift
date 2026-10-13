// AppCore+Plugins.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import PluginAI
import PluginBase64Codec
import PluginCalculator
import PluginCalendar
import PluginClipboard
import PluginHashCalculator
import PluginJSONFormatter
import PluginKillProcess
import PluginLauncher
import PluginNetworkTools
import PluginSQLFormatter
import PluginScreenshot
import PluginSystemControl
import PluginSystemMonitor
import PluginTextDiff
import PluginTimestampConverter
import PluginTranslator
import PluginURLCodec
import PluginUUIDGenerator

import Carbon.HIToolbox
import Foundation
import QuickCore
import QuickPlatform
import QuickUI
import SwiftUI

/// 插件生命周期：分离、存储迁移、注册（全仓唯一实例化插件的地方）
///
/// 从 `AppCore.swift` 按职责拆出的扩展：状态仍然只属于 `AppCore`（唯一所有者），
/// 这里只放行为。拆文件是为了让每个文件能一次读完，不是为了拆出新的所有者。
extension AppCore {

    // MARK: - 插件分离

    /// 将指定插件分离为独立窗口
    ///
    /// 查找插件实例 → 获取视图 → 创建独立窗口 → 主面板返回搜索模式。
    func detachPlugin(_ pluginID: String) {
        guard let plugin = pluginsByID[pluginID],
            plugin.isEnabled
        else {
            log.warning("分离失败：找不到插件 \(pluginID, privacy: .public) 或插件已禁用")
            return
        }

        // 视图能力是运行时查询。`PluginPanelController` 的契约是非可选视图，所以失败时
        // 退化成空视图 —— 代价是窗口空白，所以这里必须留一条 error 说明根因。
        let viewProvider = { () -> AnyView in
            guard let provider = plugin as? PluginViewProviding else {
                QuickLog.app.error(
                    "插件 \(pluginID, privacy: .public) 未实现 PluginViewProviding，分离窗口无法显示")
                return AnyView(EmptyView())
            }
            return provider.makeView()
        }
        let name = type(of: plugin).name
        let icon = type(of: plugin).icon
        let supportsSearch = type(of: plugin).supportsPanelSearch

        pluginPanelController.detach(
            pluginID: pluginID,
            pluginName: name,
            icon: icon,
            supportsSearch: supportsSearch,
            viewProvider: viewProvider,
            sourceWindow: nil
        )

        paletteCoordinator.popToRoot()
        paletteCoordinator.hide(restoreFocus: false)
    }

    // MARK: - 存储迁移

    /// 应用宿主自己的 schema
    func migrateHostStorage() {
        do {
            try database.migrate([.corePluginData, .coreUsageHistory])
        } catch {
            // 迁移失败不能静默：继续跑下去会以「表不存在」的形式在插件里炸开，
            // 那时已经看不出根因了。日志之外还要让用户知道，否则只会看到「历史记不住」
            log.error("宿主存储迁移失败：\(error)")
            databaseNotice = databaseNotice ?? "数据存储初始化失败，部分功能（最近使用、历史记录）可能无法保存"
        }
    }

    /// 应用各插件声明的 schema
    ///
    /// 表结构归插件所有，宿主只负责按注册顺序把它们跑一遍。顺序固定（注册顺序），
    /// 所以同一个库在两台机器上的建表顺序一致。
    /// - Parameter types: 插件类型列表；`storageMigrations` 是静态的，所以不需要实例
    func migratePluginStorage(_ types: [any QuickPlugin.Type]) {
        let migrations = types.flatMap { $0.storageMigrations }
        guard !migrations.isEmpty else { return }
        do {
            try database.migrate(migrations)
            log.notice("插件 schema 已就绪，共 \(migrations.count, privacy: .public) 个迁移")
        } catch {
            log.error("插件存储迁移失败：\(error)")
            databaseNotice = databaseNotice ?? "插件数据初始化失败，部分插件的数据可能无法保存"
        }
    }

    // MARK: - 插件注册

    /// 注册所有 Feature Plugin
    ///
    /// 这是唯一创建插件实例的地方。
    /// 新增插件只需在此处添加一行注册。
    /// 插件的注册清单
    ///
    /// 每一项是「类型 + 工厂」而不是直接给实例：**schema 必须在实例化之前建好**。
    /// 需要真表的插件在 `init` 里就会查自己的表（store 同步加载），如果先构造再迁移，
    /// 首次启动时表还不存在，插件会以「读取失败，按空数据继续」启动 —— 数据看起来
    /// 像是丢了，而且只在第一次运行时出现。
    ///
    /// 类型与工厂成对列出，是为了让迁移能从类型上取（`storageMigrations` 是静态的），
    /// 而依赖注入留在工厂里。
    var pluginRegistrations: [(type: any QuickPlugin.Type, make: () -> any QuickPlugin)] {
        [
            // Phase 2: 核心插件
            (
                LauncherPlugin.self,
                {
                    LauncherPlugin(
                        appIndex: self.appIndex,
                        settingsStore: self.settingsStore,
                        storage: self.storage(for: LauncherPlugin.id))
                }
            ),
            (ClipboardPlugin.self, { ClipboardPlugin(storage: self.storage(for: ClipboardPlugin.id)) }),
            (CalculatorPlugin.self, { CalculatorPlugin(storage: self.storage(for: CalculatorPlugin.id)) }),
            (SystemControlPlugin.self, { SystemControlPlugin(settingsStore: self.settingsStore) }),

            // Phase 3: 效率与工具插件
            (TranslatorPlugin.self, { TranslatorPlugin(storage: self.storage(for: TranslatorPlugin.id)) }),

            // Phase 3.5: 开发者工具插件（原先是一个 devtools 容器，现在每个工具都是独立插件）
            (JSONFormatterPlugin.self, { JSONFormatterPlugin() }),
            (SQLFormatterPlugin.self, { SQLFormatterPlugin() }),
            (Base64CodecPlugin.self, { Base64CodecPlugin() }),
            (URLCodecPlugin.self, { URLCodecPlugin() }),
            (UUIDGeneratorPlugin.self, { UUIDGeneratorPlugin() }),
            (HashCalculatorPlugin.self, { HashCalculatorPlugin() }),
            (TimestampConverterPlugin.self, { TimestampConverterPlugin() }),
            (TextDiffPlugin.self, { TextDiffPlugin() }),

            // Phase 4: 扩展插件
            (CalendarPlugin.self, { CalendarPlugin() }),
            (AIPlugin.self, { AIPlugin() }),
            (SystemMonitorPlugin.self, { SystemMonitorPlugin() }),
            (KillProcessPlugin.self, { KillProcessPlugin() }),
            (NetworkToolsPlugin.self, { NetworkToolsPlugin() }),
            (ScreenshotPlugin.self, { ScreenshotPlugin() })
        ]
    }

    /// 建表并实例化全部插件
    ///
    /// 这是全仓唯一 `plugins.append(...)` 的地方。
    func registerPlugins() {
        let registrations = pluginRegistrations

        // 先建 schema：插件的 store 在 init 里就会读表
        migratePluginStorage(registrations.map(\.type))

        // 再实例化
        for registration in registrations {
            // 构造也算「启动」：init 里崩溃同样要能指认到这个插件
            let plugin = launchGuard.guardStart(registration.type.id) { registration.make() }
            plugin.isEnabled = settingsStore.isPluginEnabled(type(of: plugin).id)
            plugins.append(plugin)
        }
    }
}
