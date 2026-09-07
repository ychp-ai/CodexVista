import AppKit
import Observation
import SwiftUI

enum StatusItemQuotaPaletteRole: Equatable {
    case fiveHour
    case weekly
}

struct StatusItemQuotaPalette {
    let start: NSColor
    let end: NSColor
    let background: NSColor
    let progressTrack: NSColor
    let text: NSColor
    let border: NSColor

    static func resolve(_ role: StatusItemQuotaPaletteRole, theme: StatusItemTheme) -> Self {
        let palette = theme.palette
        let accent = theme.color(role == .weekly ? palette.accent : palette.secondary)
        return Self(
            start: accent,
            end: accent,
            background: theme.color(palette.raised),
            progressTrack: theme.color(palette.border),
            text: theme.color(palette.primary),
            border: theme.color(palette.border)
        )
    }
}

/// Shared, explicit appearance for AppKit drawing, the notch panel and settings previews.
struct StatusItemTheme: Equatable {
    let skin: AppSkinPreference
    let dark: Bool

    static func resolve(
        skin: AppSkinPreference = .load(),
        preference: AppColorSchemePreference = .load(),
        appearance: NSAppearance
    ) -> Self {
        let dark = skin.effectiveColorScheme(for: preference).map { $0 == .dark }
            ?? (appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
        return Self(skin: skin, dark: dark)
    }

    var palette: CodexVistaPalette { .resolve(skin: skin, dark: dark) }
    var background: NSColor { color(palette.surface) }
    var primary: NSColor { color(palette.primary) }
    var countdown: NSColor { color(skin == .ink ? palette.selectedText : palette.secondary) }
    var countdownBackground: NSColor { color(palette.raised) }

    func cornerRadius(height: CGFloat) -> CGFloat {
        switch skin {
        case .standard, .celadon: height / 2
        case .ink, .cyber: 2
        case .dusk: 5
        case .xianxia: 4
        }
    }

    var valueFont: NSFont {
        skin == .cyber
            ? .monospacedSystemFont(ofSize: StatusItemLayoutMetrics.numericFontSize, weight: .semibold)
            : .monospacedDigitSystemFont(ofSize: StatusItemLayoutMetrics.numericFontSize, weight: .semibold)
    }

    func color(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

enum StatusItemLayoutMetrics {
    static let numericFontSize: CGFloat = 11
    static let imageHeight: CGFloat = 22
    static let itemOuterPadding: CGFloat = 8
    static let iconRect = NSRect(x: 2, y: 2, width: 18, height: 18)
    static let elementSpacing: CGFloat = 5
    static let leadingContentWidth: CGFloat = iconRect.maxX + elementSpacing
    static let richValueWidth: CGFloat = 38
    static let richMetricWidth: CGFloat = 58
    static let resetTextWidth: CGFloat = 26
    static let richResetWidth: CGFloat = 12 + resetTextWidth + 5
    static let richMetricSpacing: CGFloat = 5
    static let emptyImageWidth: CGFloat = 24
}

struct StatusItemMetricPresentation: Equatable, Identifiable {
    let id: String
    let label: String
    let value: String
    let fraction: CGFloat
    let resetText: String?
    let resetDescription: String?
    let paletteRole: StatusItemQuotaPaletteRole
}

struct StatusItemPresentation: Equatable {
    let metrics: [StatusItemMetricPresentation]
    let imageSize: NSSize
    let itemLength: CGFloat
    let label: String
    let tooltip: String

    init(
        snapshot: DashboardSnapshot?,
        configuration: MenuBarLabelConfiguration,
        now: Date = Date()
    ) {
        let availableQuotas = configuration.showsLivePreview
            ? snapshot?.visibleQuotas ?? []
            : []
        var selectedQuotas = availableQuotas.filter { quota in
            switch quota.id {
            case "5h": configuration.showsFiveHour
            case "7d": configuration.showsWeekly
            default: false
            }
        }
        if configuration.showsLivePreview,
           selectedQuotas.isEmpty,
           let fallback = availableQuotas.first {
            selectedQuotas = [fallback]
        }

        metrics = selectedQuotas.map { quota in
            let fraction: Double
            switch configuration.quotaDisplay {
            case .used: fraction = 1 - quota.remaining
            case .remaining: fraction = quota.remaining
            }
            let normalized = min(max(fraction, 0), 1)
            return StatusItemMetricPresentation(
                id: quota.id,
                label: quota.compactTitle,
                value: "\(Int((normalized * 100).rounded()))%",
                fraction: CGFloat(normalized),
                resetText: configuration.showsResetCountdown
                    ? quota.resetCountdown(now: now)
                    : nil,
                resetDescription: configuration.showsResetCountdown
                    ? quota.resetDescription(now: now)
                    : nil,
                paletteRole: quota.id == "7d" ? .weekly : .fiveHour
            )
        }

        let imageWidth: CGFloat
        if metrics.isEmpty {
            imageWidth = StatusItemLayoutMetrics.emptyImageWidth
        } else {
            let resetWidth = metrics.reduce(CGFloat.zero) { width, metric in
                width + (metric.resetText == nil
                    ? 0
                    : StatusItemLayoutMetrics.elementSpacing
                        + StatusItemLayoutMetrics.richResetWidth)
            }
            let metricWidth = metrics.count == 1
                ? StatusItemLayoutMetrics.richValueWidth
                : CGFloat(metrics.count) * StatusItemLayoutMetrics.richMetricWidth
            imageWidth = StatusItemLayoutMetrics.leadingContentWidth
                + metricWidth
                + CGFloat(max(0, metrics.count - 1)) * StatusItemLayoutMetrics.richMetricSpacing
                + resetWidth
                + 2
        }
        imageSize = NSSize(width: imageWidth, height: StatusItemLayoutMetrics.imageHeight)
        itemLength = imageWidth + StatusItemLayoutMetrics.itemOuterPadding
        label = metrics.isEmpty
            ? "CodexVista"
            : metrics.map { metric in
                [metric.label, metric.value, metric.resetText]
                    .compactMap { $0 }
                    .joined(separator: " ")
            }.joined(separator: " · ")
        let quotaTerm = configuration.quotaDisplay == .remaining ? "剩余" : "已用"
        let quotaDescription = metrics.map { metric in
            let quotaName = metric.id == "5h" ? "5 小时额度" : "7 天额度"
            var description = "\(quotaName) \(quotaTerm) \(metric.value)"
            if let resetDescription = metric.resetDescription {
                description += "，\(resetDescription)"
            }
            return description
        }.joined(separator: "；")
        tooltip = metrics.isEmpty
            ? configuration.showsLivePreview
                ? "CodexVista · Codex · 暂无可用额度 · 点击查看用量"
                : "CodexVista · Codex · 实时预览已关闭 · 点击查看用量"
            : "CodexVista · Codex · \(quotaDescription) · 点击查看用量"
    }
}

struct StatusItemRenderer {
    enum Style {
        case menuBar
        case notch
    }

    var style: Style = .menuBar
    var theme: StatusItemTheme?

    private var drawingTheme: StatusItemTheme {
        theme ?? .resolve(appearance: NSAppearance.currentDrawing())
    }

    private var primaryColor: NSColor {
        style == .notch ? drawingTheme.primary : .labelColor
    }

    func render(_ presentation: StatusItemPresentation, appearance: NSAppearance) -> NSImage {
        var renderedImage: NSImage?
        appearance.performAsCurrentDrawingAppearance {
            renderedImage = draw(presentation)
        }
        return renderedImage ?? draw(presentation)
    }

    private func draw(_ presentation: StatusItemPresentation) -> NSImage {
        let image = NSImage(size: presentation.imageSize)
        image.lockFocus()
        NSGraphicsContext.saveGraphicsState()
        defer {
            NSGraphicsContext.restoreGraphicsState()
            image.unlockFocus()
            image.isTemplate = false
        }

        NSGraphicsContext.current?.imageInterpolation = .high
        drawIcon(in: StatusItemLayoutMetrics.iconRect, themed: !presentation.metrics.isEmpty || style == .notch)
        drawRich(presentation.metrics)
        return image
    }

    private func drawRich(_ metrics: [StatusItemMetricPresentation]) {
        var x = StatusItemLayoutMetrics.leadingContentWidth
        let showsPeriodLabels = metrics.count > 1
        for (index, metric) in metrics.enumerated() {
            if index > 0 {
                x += StatusItemLayoutMetrics.richMetricSpacing
            }

            if showsPeriodLabels {
                drawText(
                    metric.label,
                    in: NSRect(x: x, y: 4, width: 17, height: 14),
                    font: .monospacedDigitSystemFont(ofSize: 9.8, weight: .semibold),
                    color: primaryColor,
                    alignment: .right
                )
            }
            let valueOffset: CGFloat = showsPeriodLabels ? 20 : 0
            drawValuePill(
                metric.value,
                fraction: metric.fraction,
                paletteRole: metric.paletteRole,
                in: NSRect(
                    x: x + valueOffset,
                    y: 2,
                    width: StatusItemLayoutMetrics.richValueWidth,
                    height: 18
                )
            )
            x += showsPeriodLabels
                ? StatusItemLayoutMetrics.richMetricWidth
                : StatusItemLayoutMetrics.richValueWidth

            if let resetText = metric.resetText {
                x += StatusItemLayoutMetrics.elementSpacing
                drawResetCountdown(resetText, x: x)
                x += StatusItemLayoutMetrics.richResetWidth
            }
        }
    }

    private func drawValuePill(
        _ value: String,
        fraction: CGFloat,
        paletteRole: StatusItemQuotaPaletteRole,
        in rect: NSRect
    ) {
        let palette = StatusItemQuotaPalette.resolve(paletteRole, theme: drawingTheme)
        drawValueBackground(in: rect, palette: palette)
        drawLinearProgress(
            in: rect,
            fraction: fraction,
            palette: palette
        )
        drawText(
            value,
            in: NSRect(x: rect.minX, y: rect.minY + 4,
                       width: rect.width, height: 14),
            font: drawingTheme.valueFont,
            color: palette.text,
            alignment: .center
        )
    }

    private func drawValueBackground(in rect: NSRect, palette: StatusItemQuotaPalette) {
        let path = NSBezierPath(
            roundedRect: rect,
            xRadius: drawingTheme.cornerRadius(height: rect.height),
            yRadius: drawingTheme.cornerRadius(height: rect.height)
        )
        palette.background.setFill()
        path.fill()
        palette.border.setStroke()
        path.lineWidth = 0.8
        path.stroke()
    }

    private func drawLinearProgress(
        in rect: NSRect,
        fraction: CGFloat,
        palette: StatusItemQuotaPalette
    ) {
        let progressRect = NSRect(
            x: rect.minX + 5,
            y: rect.minY + 2,
            width: rect.width - 10,
            height: 1.8
        )
        if drawingTheme.skin == .cyber {
            let segments = NSBezierPath()
            let step = progressRect.width / 7
            for index in 0..<7 {
                segments.appendRect(NSRect(x: progressRect.minX + CGFloat(index) * step, y: progressRect.minY,
                                           width: step - 1, height: progressRect.height))
            }
            palette.progressTrack.setFill()
            segments.fill()
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: NSRect(x: progressRect.minX, y: progressRect.minY,
                                     width: progressRect.width * min(max(fraction, 0), 1), height: progressRect.height)).addClip()
            palette.start.setFill()
            segments.fill()
            NSGraphicsContext.restoreGraphicsState()
            return
        }
        palette.progressTrack.setFill()
        NSBezierPath(
            roundedRect: progressRect,
            xRadius: progressRect.height / 2,
            yRadius: progressRect.height / 2
        ).fill()

        let normalized = min(max(fraction, 0), 1)
        guard normalized > 0 else { return }
        let fillWidth = max(progressRect.height, progressRect.width * normalized)
        let fillRect = NSRect(
            x: progressRect.minX,
            y: progressRect.minY,
            width: fillWidth,
            height: progressRect.height
        )
        let fillPath = NSBezierPath(
            roundedRect: fillRect,
            xRadius: fillRect.height / 2,
            yRadius: fillRect.height / 2
        )
        guard let context = NSGraphicsContext.current?.cgContext,
              let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [palette.start.cgColor, palette.end.cgColor] as CFArray,
                locations: [0, 1]
              )
        else {
            palette.end.setFill()
            fillPath.fill()
            return
        }
        context.saveGState()
        fillPath.addClip()
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: fillRect.minX, y: fillRect.midY),
            end: CGPoint(x: fillRect.maxX, y: fillRect.midY),
            options: []
        )
        context.restoreGState()
    }

    private func drawResetCountdown(_ value: String, x: CGFloat) {
        let color = drawingTheme.countdown
        let backgroundRect = NSRect(
            x: x,
            y: 3,
            width: StatusItemLayoutMetrics.richResetWidth - 2,
            height: 16
        )
        drawingTheme.countdownBackground.setFill()
        let background = NSBezierPath(
            roundedRect: backgroundRect,
            xRadius: drawingTheme.cornerRadius(height: backgroundRect.height),
            yRadius: drawingTheme.cornerRadius(height: backgroundRect.height)
        )
        background.fill()
        drawingTheme.color(drawingTheme.palette.border).setStroke()
        background.lineWidth = 0.8
        background.stroke()

        let iconRect = NSRect(x: x + 3, y: 7, width: 8, height: 8)
        if let symbol = NSImage(
            systemSymbolName: "arrow.clockwise",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 8, weight: .bold)) {
            drawTintedImage(symbol, color: color, in: iconRect)
        }
        drawText(
            value,
            in: NSRect(
                x: x + 12,
                y: 3,
                width: StatusItemLayoutMetrics.resetTextWidth,
                height: 16
            ),
            font: .monospacedDigitSystemFont(ofSize: StatusItemLayoutMetrics.numericFontSize, weight: .semibold),
            color: color,
            alignment: .left
        )
    }

    private func drawText(
        _ value: String,
        in rect: NSRect,
        font: NSFont,
        color: NSColor,
        alignment: NSTextAlignment
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        let text = NSAttributedString(
            string: value,
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
        )
        text.draw(in: rect)
    }

    private func drawIcon(in rect: NSRect, themed: Bool) {
        guard let source = NSImage(named: "MenuBarIcon") else { return }
        if themed {
            drawingTheme.background.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
            let palette = drawingTheme.palette
            drawTintedImage(source, color: drawingTheme.color(drawingTheme.skin == .ink ? palette.selectedText : palette.accent),
                            in: rect.insetBy(dx: 1, dy: 1))
        } else {
            // The icon-only entry sits directly on the system menu bar / wallpaper.
            drawTintedImage(source, color: primaryColor, in: rect)
        }
    }

    private func drawTintedImage(_ source: NSImage, color: NSColor, in rect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        source.draw(
            in: rect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        context.setBlendMode(.sourceIn)
        context.setFillColor(color.cgColor)
        context.fill(rect)
        context.setBlendMode(.normal)
        context.endTransparencyLayer()
    }
}

@MainActor
final class StatusItemController: NSObject {
    private let store: DashboardStore
    private let updateService: AppUpdateService
    private let defaults: UserDefaults
    private let notchSummary = NotchSummaryController()
    private var notchFrame: NSRect?
    private var refreshTimer: Timer?
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    private var popover: NSPopover?
    private var popoverNeedsFocus = false
    private var appearanceObservation: NSKeyValueObservation?
    private var lastPresentation: StatusItemPresentation?
    private var lastAppearanceName: NSAppearance.Name?
    private var lastTheme: StatusItemTheme?
    private var onOpenDashboard: () -> Void
    private var onOpenSettings: () -> Void

    init(
        store: DashboardStore,
        updateService: AppUpdateService,
        defaults: UserDefaults = .standard,
        onOpenDashboard: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.store = store
        self.updateService = updateService
        self.defaults = defaults
        self.onOpenDashboard = onOpenDashboard
        self.onOpenSettings = onOpenSettings
        super.init()
        install()
    }

    isolated deinit {
        refreshTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    func updateActions(
        onOpenDashboard: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.onOpenDashboard = onOpenDashboard
        self.onOpenSettings = onOpenSettings
    }

    func closePopover() {
        popoverNeedsFocus = false
        popover?.performClose(nil)
        popover = nil
    }

    private func install() {
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.target = self
        button.action = #selector(statusItemClicked)
        button.setAccessibilityLabel("CodexVista")

        appearanceObservation = button.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.updateStatusItem()
            }
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(defaultsDidChange),
            name: UserDefaults.didChangeNotification,
            object: defaults
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: NSApp
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateStatusItem() }
        }
        observeStore()
        updateStatusItem()
    }

    private func observeStore() {
        withObservationTracking {
            _ = store.state
            _ = store.isRefreshing
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.observeStore()
                self?.updateStatusItem()
            }
        }
    }

    @objc nonisolated private func defaultsDidChange() {
        DispatchQueue.main.async { [weak self] in
            self?.updateStatusItem()
        }
    }

    @objc private func applicationDidBecomeActive(_ notification: Notification) {
        focusPopoverIfReady()
    }

    @objc private func screenParametersDidChange(_ notification: Notification) {
        closePopover()
        updateStatusItem()
    }

    @objc private func statusItemClicked() {
        if popover?.isShown == true {
            closePopover()
        } else {
            showPopover()
        }
    }

    private func showPopover(from anchor: NSView? = nil) {
        guard let button = anchor ?? statusItem.button else { return }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        let content = CodexVistaAppearanceContainer {
            MenuBarPopoverView(
                store: store,
                updateService: updateService,
                onOpenDashboard: { [weak self] in
                    self?.closePopover()
                    self?.onOpenDashboard()
                },
                onOpenSettings: { [weak self] in
                    self?.closePopover()
                    self?.onOpenSettings()
                }
            )
        }
        let hostingController = NSHostingController(rootView: content)
        popover.contentViewController = hostingController
        hostingController.view.layoutSubtreeIfNeeded()
        popover.contentSize = hostingController.view.fittingSize
        self.popover = popover
        popoverNeedsFocus = true
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        focusPopoverIfReady()
        if !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func focusPopoverIfReady() {
        guard popoverNeedsFocus,
              let popover,
              popover.isShown,
              let window = popover.contentViewController?.view.window else {
            return
        }
        window.makeKey()
        popoverNeedsFocus = false
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let configuration = menuBarConfiguration
        let appearance = button.effectiveAppearance
        let theme = StatusItemTheme.resolve(skin: .load(from: defaults), preference: .load(from: defaults), appearance: appearance)
        let fullPresentation = StatusItemPresentation(
            snapshot: store.snapshot,
            configuration: configuration
        )
        let contentWidth = NotchSummaryLayout.width(
            for: fullPresentation,
            quotaDisplay: configuration.quotaDisplay
        )
        let nextNotchFrame = SummaryPlacementPreference.load(from: defaults) == .notch
            && configuration.showsLivePreview
            ? NSScreen.screens.compactMap { NotchSummaryLayout.frame(on: $0, contentWidth: contentWidth) }.first
            : nil
        if nextNotchFrame != notchFrame {
            closePopover()
            notchFrame = nextNotchFrame
        }
        if let notchFrame {
            notchSummary.update(
                frame: notchFrame,
                presentation: fullPresentation,
                quotaDisplay: configuration.quotaDisplay,
                theme: theme
            ) { [weak self] in
                guard let self else { return }
                if self.popover?.isShown == true {
                    self.closePopover()
                } else {
                    self.showPopover(from: self.notchSummary.anchorView)
                }
            }
        } else {
            notchSummary.hide()
        }
        let presentation = StatusItemPresentation(
            snapshot: store.snapshot,
            configuration: notchFrame == nil ? configuration : MenuBarLabelConfiguration(
                showsLivePreview: false,
                quotaDisplay: configuration.quotaDisplay,
                showsFiveHour: false,
                showsWeekly: true,
                showsResetCountdown: configuration.showsResetCountdown
            )
        )
        button.toolTip = fullPresentation.tooltip
        button.setAccessibilityValue(fullPresentation.label)
        guard presentation != lastPresentation || appearance.name != lastAppearanceName || theme != lastTheme else { return }

        lastPresentation = presentation
        lastAppearanceName = appearance.name
        lastTheme = theme
        statusItem.length = presentation.itemLength
        button.image = StatusItemRenderer(theme: theme).render(presentation, appearance: appearance)
    }

    private var menuBarConfiguration: MenuBarLabelConfiguration {
        MenuBarLabelConfiguration(
            showsLivePreview: defaults.object(forKey: AppPreferenceKeys.showsLivePreview) as? Bool ?? true,
            quotaDisplay: QuotaDisplayPreference(
                rawValue: defaults.string(forKey: AppPreferenceKeys.quotaDisplay) ?? ""
            ) ?? .remaining,
            showsFiveHour: false,
            showsWeekly: true,
            showsResetCountdown: defaults.object(forKey: AppPreferenceKeys.showsResetCountdown) as? Bool ?? true
        )
    }

}

extension StatusItemController: NSPopoverDelegate {
    func popoverDidShow(_ notification: Notification) {
        guard let shownPopover = notification.object as? NSPopover,
              shownPopover === popover else {
            return
        }
        focusPopoverIfReady()
    }
}
