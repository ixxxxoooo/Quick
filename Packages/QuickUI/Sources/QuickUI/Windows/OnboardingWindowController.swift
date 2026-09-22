// OnboardingWindowController.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import ApplicationServices
import SwiftUI

/// 第一次打开时的引导。排版对齐 jietu：顶部说明、卡片行、步骤点、稍后 / 继续
@MainActor
public final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let log = QuickLog.ui

    /// 登录时打开，由 AppCore 接上系统服务。引导页自己不持有平台层
    public var isLaunchAtLoginEnabled: () -> Bool = { false }
    public var setLaunchAtLogin: (Bool) -> Void = { _ in }

    public func presentIfNeeded() {
        guard UserDefaults.standard.object(forKey: SettingsKey.onboardingCompleted) == nil else { return }
        present()
    }

    public func present() {
        let window = self.window ?? makeWindow()
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        log.notice("已打开首次引导")
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(
            rootView: OnboardingView(
                isLaunchAtLoginEnabled: isLaunchAtLoginEnabled,
                setLaunchAtLogin: setLaunchAtLogin,
                onFinish: { [weak self] in
                    UserDefaults.standard.set(true, forKey: SettingsKey.onboardingCompleted)
                    self?.window?.close()
                    self?.log.notice("首次引导已完成")
                }
            )
        )
        let window = NSWindow(contentViewController: hosting)
        window.title = "欢迎使用 Quick"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.setContentSize(
            NSSize(width: DesignTokens.Size.onboardingWidth, height: DesignTokens.Size.onboardingMinHeight)
        )
        window.delegate = self
        self.window = window
        return window
    }
}

/// 引导步骤
private struct OnboardingView: View {
    let isLaunchAtLoginEnabled: () -> Bool
    let setLaunchAtLogin: (Bool) -> Void
    let onFinish: () -> Void

    @State private var step = 0
    @State private var launchAtLogin = false
    @State private var accessibilityGranted = false
    @State private var screenGranted = false

    private static let lastStep = 3

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            hero
            stepContent
            footer
        }
        .padding(.top, DesignTokens.Spacing.xs)
        .padding([.horizontal, .bottom], DesignTokens.Spacing.xxl)
        .frame(width: DesignTokens.Size.onboardingWidth)
        .background(alignment: .top) {
            LinearGradient(
                colors: [DesignTokens.Colors.panelEdgeHighlight, Color.clear],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()
        }
        .task {
            launchAtLogin = isLaunchAtLoginEnabled()
            while !Task.isCancelled {
                refreshPermissions()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var hero: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            heroMark
            VStack(spacing: DesignTokens.Spacing.xs) {
                Text(title)
                    .font(DesignTokens.Typography.rowTitle)
                Text(subtitle)
                    .font(DesignTokens.Typography.rowTrailing)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var heroMark: some View {
        if step == 0 {
            Image(nsImage: Self.appIcon)
                .resizable()
                .frame(width: DesignTokens.Size.onboardingHero, height: DesignTokens.Size.onboardingHero)
        } else {
            Image(systemName: heroSymbol)
                .font(DesignTokens.Typography.emptyStateIcon)
                .foregroundStyle(heroTint)
                .frame(width: DesignTokens.Size.onboardingHero, height: DesignTokens.Size.onboardingHero)
                .background(Circle().fill(DesignTokens.Colors.controlSurface))
        }
    }

    private var title: String {
        switch step {
        case 0: "欢迎使用 Quick"
        case 1: "授权系统能力"
        case 2: "用关键字唤醒"
        default: "可以开始了"
        }
    }

    private var subtitle: String {
        switch step {
        case 0: "一个面板里启动应用、查剪贴板、做计算。功能用关键字唤醒，不各绑一套全局热键。"
        case 1:
            screenGranted && accessibilityGranted
                ? "两项都已打开。回到 Quick 后会自动刷新。"
                : "把 Quick 拖进系统设置的列表，再打开开关。定位只在查看天气时才申请。"
        case 2: "一个功能可以有多个关键字。不同关键字可以打开同一个插件里的不同功能。"
        default: "⌥Space 唤出面板。在搜索框输入关键字，回车就执行。"
        }
    }

    private var heroSymbol: String {
        switch step {
        case 1: "hand.raised"
        case 2: "text.cursor"
        default: "checkmark"
        }
    }

    private var heroTint: Color {
        switch step {
        case 1: screenGranted && accessibilityGranted ? DesignTokens.Colors.success : Color.accentColor
        case 2: DesignTokens.Colors.warning
        default: DesignTokens.Colors.success
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0: welcomeStep
        case 1: permissionStep
        case 2: keywordStep
        default: doneStep
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            OnboardingCard {
                OnboardingRow(
                    title: "登录时打开",
                    subtitle: "开机后菜单栏里就有 Quick",
                    systemImage: "power",
                    tint: DesignTokens.Colors.success
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { launchAtLogin },
                            set: { enabled in
                                launchAtLogin = enabled
                                setLaunchAtLogin(enabled)
                            }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
            }
            caption("这一项以后可以在设置里改。")
        }
    }

    private var permissionStep: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            OnboardingCard {
                OnboardingRow(
                    title: "屏幕录制",
                    subtitle: screenGranted ? "已授权" : "截图和取色需要它",
                    systemImage: "camera.viewfinder",
                    tint: screenGranted ? DesignTokens.Colors.success : Color.accentColor
                ) {
                    OnboardingStatusBadge(
                        title: screenGranted ? "已授权" : "未授权",
                        systemImage: screenGranted
                            ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                        tint: screenGranted ? DesignTokens.Colors.success : DesignTokens.Colors.warning
                    )
                }
                OnboardingDivider()
                OnboardingRow(
                    title: "辅助功能",
                    subtitle: accessibilityGranted ? "已授权" : "系统控制需要它",
                    systemImage: "hand.tap",
                    tint: accessibilityGranted ? DesignTokens.Colors.success : Color.accentColor
                ) {
                    OnboardingStatusBadge(
                        title: accessibilityGranted ? "已授权" : "未授权",
                        systemImage: accessibilityGranted
                            ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                        tint: accessibilityGranted ? DesignTokens.Colors.success : DesignTokens.Colors.warning
                    )
                }
            }
            HStack {
                caption(
                    screenGranted && accessibilityGranted
                        ? "在系统设置里关掉之后，重启 Quick 才会显示成未授权。"
                        : "卡片会贴在系统设置窗口下面，拖进右侧列表。")
                Spacer(minLength: 0)
                Button("重新检测") { refreshPermissions() }
                    .buttonStyle(.link)
                    .font(DesignTokens.Typography.keyCap)
            }
        }
    }

    private var keywordStep: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            OnboardingCard {
                OnboardingRow(
                    title: "截图",
                    subtitle: "打开区域截图",
                    systemImage: "rectangle.dashed",
                    tint: Color.accentColor
                ) {
                    keywordChip("截图")
                }
                OnboardingDivider()
                OnboardingRow(
                    title: "全屏截图",
                    subtitle: "截下整个屏幕",
                    systemImage: "rectangle.on.rectangle",
                    tint: Color.accentColor
                ) {
                    keywordChip("全屏")
                }
                OnboardingDivider()
                OnboardingRow(
                    title: "锁屏",
                    subtitle: "系统控制里的另一个功能",
                    systemImage: "lock",
                    tint: Color.accentColor
                ) {
                    keywordChip("锁屏")
                }
            }
            caption("快捷键页把一条按键绑到关键字上。对不上，或同时对上多条，不会猜。")
        }
    }

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            OnboardingCard {
                OnboardingRow(
                    title: "从菜单栏打开",
                    subtitle: "点菜单栏图标，或按 ⌥Space",
                    systemImage: "menubar.rectangle",
                    tint: Color.accentColor
                )
                OnboardingDivider()
                OnboardingRow(
                    title: "每个插件有自己的设置页",
                    subtitle: "关键字、开关和说明都在那一页",
                    systemImage: "gearshape",
                    tint: DesignTokens.Colors.textSecondary
                )
            }
            caption("面板底边可以拖高矮，搜索栏左侧的手柄可以拖动位置。")
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var footer: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                ForEach(0...Self.lastStep, id: \.self) { index in
                    Circle()
                        .fill(index == step ? Color.primary : DesignTokens.Colors.textTertiary)
                        .frame(
                            width: DesignTokens.Size.onboardingDot, height: DesignTokens.Size.onboardingDot)
                }
            }
            HStack {
                if step > 0 {
                    Button {
                        step -= 1
                    } label: {
                        Label("上一步", systemImage: "chevron.left")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                Spacer()
                if step == 1 || step == 2 {
                    Button("稍后") { advance() }
                        .buttonStyle(.plain)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                Button(primaryTitle, action: primaryAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var primaryTitle: String {
        switch step {
        case 1 where !screenGranted: "授权屏幕录制"
        case 1 where !accessibilityGranted: "授权辅助功能"
        case Self.lastStep: "开始使用"
        default: "继续"
        }
    }

    private func primaryAction() {
        switch step {
        case 1 where !screenGranted:
            PermissionDragController.shared.present(.screenCapture)
        case 1 where !accessibilityGranted:
            PermissionDragController.shared.present(.accessibility)
        case Self.lastStep:
            onFinish()
        default:
            advance()
        }
    }

    private func advance() {
        step = min(step + 1, Self.lastStep)
    }

    private func refreshPermissions() {
        accessibilityGranted = AXIsProcessTrusted()
        screenGranted = CGPreflightScreenCaptureAccess()
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(DesignTokens.Typography.keyCap)
            .foregroundStyle(DesignTokens.Colors.textTertiary)
    }

    private func keywordChip(_ text: String) -> some View {
        Text(text)
            .font(DesignTokens.Typography.compactKeyCap)
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .background(Capsule().fill(DesignTokens.Colors.controlSurface))
    }

    private static let appIcon: NSImage = {
        if let name = Bundle.main.infoDictionary?["CFBundleIconFile"] as? String,
            let url = Bundle.main.url(forResource: name, withExtension: "icns"),
            let image = NSImage(contentsOf: url)
        {
            return image
        }
        return NSApp.applicationIconImage ?? NSImage()
    }()
}

/// 一组引导行的圆角容器
private struct OnboardingCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                    .fill(DesignTokens.Colors.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                    .strokeBorder(DesignTokens.Colors.cardStroke, lineWidth: DesignTokens.Size.hairline)
            )
    }
}

private struct OnboardingDivider: View {
    var body: some View {
        Rectangle()
            .fill(DesignTokens.Colors.cardStroke)
            .frame(height: DesignTokens.Size.hairline)
            .padding(.leading, DesignTokens.Spacing.xl + DesignTokens.Size.rowIcon + DesignTokens.Spacing.lg)
    }
}

private struct OnboardingRow<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var systemImage: String?
    var tint: Color = DesignTokens.Colors.textSecondary
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.lg) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(DesignTokens.Typography.compactIcon)
                    .foregroundStyle(tint)
                    .frame(width: DesignTokens.Size.rowIcon)
            }
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text(title)
                    .font(DesignTokens.Typography.rowTitle)
                if let subtitle {
                    Text(subtitle)
                        .font(DesignTokens.Typography.rowTrailing)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: DesignTokens.Spacing.xl)
            trailing
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.vertical, DesignTokens.Spacing.lg)
    }
}

private extension OnboardingRow where Trailing == EmptyView {
    init(
        title: String, subtitle: String? = nil, systemImage: String? = nil,
        tint: Color = DesignTokens.Colors.textSecondary
    ) {
        self.init(title: title, subtitle: subtitle, systemImage: systemImage, tint: tint) {
            EmptyView()
        }
    }
}

private struct OnboardingStatusBadge: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: systemImage)
            Text(title)
        }
        .font(DesignTokens.Typography.keyCap)
        .foregroundStyle(tint)
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.xs)
        .background(Capsule().fill(DesignTokens.Colors.controlSurface))
    }
}
