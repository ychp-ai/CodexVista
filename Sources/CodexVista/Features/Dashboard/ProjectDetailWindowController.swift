import AppKit
import SwiftUI

@MainActor
final class ProjectDetailWindowController: NSWindowController, NSWindowDelegate {
    private weak var parentWindow: NSWindow?
    private var hostingController: NSHostingController<AnyView>?
    private var detailHoverPanel: NSPanel?
    private var detailHoverHostingController: NSHostingController<AnyView>?
    private var parentCloseObserver: NSObjectProtocol?
    private var parentClickMonitor: Any?
    private let dismissesOnParentClick: Bool
    private var lastChildOrigin: NSPoint?
    private var isSynchronizingMove = false
    private var isDismissing = false
    private var parentIgnoredMouseEvents = false
    private let onDismiss: () -> Void

    convenience init(
        entry: WorkspaceUsageEntry,
        rank: Int,
        range: ActivityRange,
        parentWindow: NSWindow,
        onDismiss: @escaping () -> Void
    ) {
        self.init(
            title: "项目详情",
            parentWindow: parentWindow,
            onDismiss: onDismiss
        )
        update(entry: entry, rank: rank, range: range)
    }

    convenience init(
        task: TodayTaskUsageEntry,
        parentWindow: NSWindow,
        onDismiss: @escaping () -> Void
    ) {
        self.init(
            title: "今日任务详情",
            parentWindow: parentWindow,
            dismissesOnParentClick: true,
            onDismiss: onDismiss
        )
        update(task: task)
    }

    private init(
        title: String,
        parentWindow: NSWindow,
        dismissesOnParentClick: Bool = false,
        onDismiss: @escaping () -> Void
    ) {
        self.dismissesOnParentClick = dismissesOnParentClick
        self.parentWindow = parentWindow
        self.onDismiss = onDismiss

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 570),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init(window: panel)

        panel.title = title
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.titlebarSeparatorStyle = .none
        panel.backgroundColor = .windowBackgroundColor
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .documentWindow
        panel.minSize = NSSize(width: 760, height: 560)
        panel.level = parentWindow.level
        panel.collectionBehavior = [.fullScreenAuxiliary]
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.delegate = self

        let hostingController = NSHostingController(
            rootView: AnyView(
                CodexVistaAppearanceContainer {
                    EmptyView()
                }
            )
        )
        self.hostingController = hostingController
        panel.contentViewController = hostingController

        parentCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: parentWindow,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.dismiss(reactivateParent: false)
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let panel = window, let parentWindow else { return }

        let width = max(760, min(820, parentWindow.frame.width - 72))
        let height = max(580, min(680, parentWindow.frame.height - 24))
        let origin = NSPoint(
            x: parentWindow.frame.midX - width / 2,
            y: parentWindow.frame.midY - height / 2
        )
        panel.setFrame(NSRect(x: origin.x, y: origin.y, width: width, height: height), display: true)

        parentIgnoredMouseEvents = parentWindow.ignoresMouseEvents
        if dismissesOnParentClick {
            parentClickMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            ) { [weak self] event in
                let didDismiss = MainActor.assumeIsolated {
                    guard let self, event.window === self.parentWindow else { return false }
                    self.dismiss()
                    return true
                }
                // Consume the dismissal click so it cannot activate a control underneath.
                return didDismiss ? nil : event
            }
        } else {
            parentWindow.ignoresMouseEvents = true
        }
        parentWindow.addChildWindow(panel, ordered: .above)
        lastChildOrigin = panel.frame.origin
        panel.makeKeyAndOrderFront(nil)
    }

    func update(entry: WorkspaceUsageEntry, rank: Int, range: ActivityRange) {
        hostingController?.rootView = AnyView(
            CodexVistaAppearanceContainer {
                ProjectDetailView(
                    entry: entry,
                    rank: rank,
                    range: range,
                    onClose: { [weak self] in
                        self?.dismiss()
                    },
                    onDetailHover: { [weak self] item in
                        self?.updateDetailHover(item)
                    }
                )
            }
        )
    }

    func update(task: TodayTaskUsageEntry) {
        hostingController?.rootView = AnyView(
            CodexVistaAppearanceContainer {
                TodayTaskDetailView(
                    task: task,
                    onClose: { [weak self] in
                        self?.dismiss()
                    },
                    onReplyHover: { [weak self] row in
                        self?.updateDetailHover(row.map(ProjectDetailHoverItem.reply))
                    }
                )
            }
        )
    }

    func dismiss() {
        dismiss(reactivateParent: true)
    }

    private func dismiss(reactivateParent: Bool) {
        guard !isDismissing else { return }
        isDismissing = true

        if let parentCloseObserver {
            NotificationCenter.default.removeObserver(parentCloseObserver)
            self.parentCloseObserver = nil
        }

        if let parentClickMonitor {
            NSEvent.removeMonitor(parentClickMonitor)
            self.parentClickMonitor = nil
        }

        closeDetailHoverPanel()

        if let panel = window {
            panel.delegate = nil
            parentWindow?.removeChildWindow(panel)
            panel.orderOut(nil)
            panel.close()
        }

        if let parentWindow {
            parentWindow.ignoresMouseEvents = parentIgnoredMouseEvents
            if reactivateParent {
                parentWindow.makeKeyAndOrderFront(nil)
            }
        }

        onDismiss()
    }

    private func updateDetailHover(_ item: ProjectDetailHoverItem?) {
        guard let item else {
            hideDetailHoverPanel()
            return
        }
        guard let detailPanel = window else { return }

        let content: AnyView
        switch item {
        case .conversation(let conversation):
            content = AnyView(ProjectConversationHoverCard(conversation: conversation))
        case .reply(let row):
            content = AnyView(ProjectReplyHoverCard(row: row))
        }
        let rootView = AnyView(
            CodexVistaAppearanceContainer {
                content.padding(12)
            }
        )
        let hostingController: NSHostingController<AnyView>
        let hoverPanel: NSPanel

        if let existingHostingController = detailHoverHostingController,
           let existingPanel = detailHoverPanel {
            existingHostingController.rootView = rootView
            hostingController = existingHostingController
            hoverPanel = existingPanel
        } else {
            hostingController = NSHostingController(rootView: rootView)
            hoverPanel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 434, height: 320),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            hoverPanel.contentViewController = hostingController
            hoverPanel.backgroundColor = .clear
            hoverPanel.isOpaque = false
            hoverPanel.hasShadow = true
            hoverPanel.ignoresMouseEvents = true
            hoverPanel.hidesOnDeactivate = false
            hoverPanel.isReleasedWhenClosed = false
            hoverPanel.animationBehavior = .utilityWindow
            hoverPanel.level = detailPanel.level
            hoverPanel.collectionBehavior = [
                .fullScreenAuxiliary,
                .transient,
                .ignoresCycle
            ]
            detailHoverHostingController = hostingController
            detailHoverPanel = hoverPanel
        }

        hostingController.view.layoutSubtreeIfNeeded()
        let fittingSize = hostingController.view.fittingSize
        let maximumHeight = max(
            230,
            (detailPanel.screen?.visibleFrame.height ?? 680) - 24
        )
        hoverPanel.setContentSize(
            NSSize(
                width: max(434, fittingSize.width),
                height: min(max(230, fittingSize.height), maximumHeight)
            )
        )
        positionDetailHoverPanel(hoverPanel, relativeTo: detailPanel)

        if hoverPanel.parent !== detailPanel {
            hoverPanel.parent?.removeChildWindow(hoverPanel)
            detailPanel.addChildWindow(hoverPanel, ordered: .above)
        }
        hoverPanel.orderFront(nil)
    }

    private func positionDetailHoverPanel(
        _ hoverPanel: NSPanel,
        relativeTo detailPanel: NSWindow
    ) {
        guard let screen = detailPanel.screen ?? NSScreen.main else { return }

        let gap: CGFloat = 10
        let screenFrame = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        let detailFrame = detailPanel.frame
        let hoverSize = hoverPanel.frame.size
        let rightOriginX = detailFrame.maxX + gap
        let leftOriginX = detailFrame.minX - hoverSize.width - gap
        let sideOriginY = min(
            max(detailFrame.maxY - 218 - hoverSize.height, screenFrame.minY),
            screenFrame.maxY - hoverSize.height
        )
        let origin: NSPoint
        if rightOriginX + hoverSize.width <= screenFrame.maxX {
            origin = NSPoint(x: rightOriginX, y: sideOriginY)
        } else if leftOriginX >= screenFrame.minX {
            origin = NSPoint(x: leftOriginX, y: sideOriginY)
        } else if detailFrame.minY - gap - hoverSize.height >= screenFrame.minY {
            origin = NSPoint(
                x: min(
                    max(detailFrame.maxX - hoverSize.width, screenFrame.minX),
                    screenFrame.maxX - hoverSize.width
                ),
                y: detailFrame.minY - gap - hoverSize.height
            )
        } else if detailFrame.maxY + gap + hoverSize.height <= screenFrame.maxY {
            origin = NSPoint(
                x: min(
                    max(detailFrame.maxX - hoverSize.width, screenFrame.minX),
                    screenFrame.maxX - hoverSize.width
                ),
                y: detailFrame.maxY + gap
            )
        } else {
            let rightSpace = screenFrame.maxX - detailFrame.maxX
            let leftSpace = detailFrame.minX - screenFrame.minX
            origin = NSPoint(
                x: rightSpace >= leftSpace
                    ? screenFrame.maxX - hoverSize.width
                    : screenFrame.minX,
                y: sideOriginY
            )
        }
        hoverPanel.setFrameOrigin(origin)
    }

    private func hideDetailHoverPanel() {
        guard let hoverPanel = detailHoverPanel else { return }
        hoverPanel.parent?.removeChildWindow(hoverPanel)
        hoverPanel.orderOut(nil)
    }

    private func closeDetailHoverPanel() {
        guard let hoverPanel = detailHoverPanel else { return }
        hoverPanel.parent?.removeChildWindow(hoverPanel)
        hoverPanel.orderOut(nil)
        hoverPanel.close()
        detailHoverPanel = nil
        detailHoverHostingController = nil
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        dismiss()
        return false
    }

    func windowDidMove(_ notification: Notification) {
        guard
            let childWindow = notification.object as? NSWindow,
            childWindow === window,
            let parentWindow,
            !isSynchronizingMove
        else {
            return
        }

        let currentOrigin = childWindow.frame.origin
        guard let previousOrigin = lastChildOrigin else {
            lastChildOrigin = currentOrigin
            return
        }
        lastChildOrigin = currentOrigin

        guard NSEvent.pressedMouseButtons & 1 == 1 else { return }
        let delta = NSPoint(
            x: currentOrigin.x - previousOrigin.x,
            y: currentOrigin.y - previousOrigin.y
        )
        guard abs(delta.x) > 0.1 || abs(delta.y) > 0.1 else { return }

        isSynchronizingMove = true
        parentWindow.removeChildWindow(childWindow)
        parentWindow.setFrameOrigin(
            NSPoint(
                x: parentWindow.frame.origin.x + delta.x,
                y: parentWindow.frame.origin.y + delta.y
            )
        )
        childWindow.setFrameOrigin(currentOrigin)
        parentWindow.addChildWindow(childWindow, ordered: .above)
        lastChildOrigin = childWindow.frame.origin
        isSynchronizingMove = false
    }
}
