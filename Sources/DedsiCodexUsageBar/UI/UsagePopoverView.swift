import AppKit

final class UsagePopoverController: NSObject {
    private let panel: NSPanel
    private let content = UsagePanelView(frame: NSRect(x: 0, y: 0, width: 280, height: 220))
    private weak var statusItem: NSStatusItem?
    private var eventMonitor: Any?

    override init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 220),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        super.init()

        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true

        let container = VisualContainerView(frame: NSRect(x: 0, y: 0, width: 280, height: 220))
        content.frame = container.bounds.insetBy(dx: 0, dy: 0)
        content.autoresizingMask = [.width, .height]
        container.addSubview(content)
        panel.contentView = container
    }

    func attach(to statusItem: NSStatusItem) {
        self.statusItem = statusItem
        content.onRefresh = { [weak self] in
            Task { @MainActor in
                await UsageViewModel.shared.refresh()
                self?.reload()
            }
        }
        content.onQuit = {
            NSApp.terminate(nil)
        }
        content.onToggleLogin = { enabled in
            UsageViewModel.shared.launchAtLogin = enabled
        }
    }

    var isShown: Bool { panel.isVisible }

    func toggle() {
        if panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        reload()
        guard let button = statusItem?.button, let window = button.window else { return }

        let buttonRect = button.convert(button.bounds, to: nil)
        let screenRect = window.convertToScreen(buttonRect)
        let size = panel.frame.size
        let x = screenRect.midX - size.width / 2
        let y = screenRect.minY - size.height - 6
        panel.setFrameOrigin(NSPoint(x: max(8, x), y: max(8, y)))
        panel.orderFront(nil)

        // Delay monitor so the opening click doesn't immediately dismiss the panel.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.startMonitor()
        }

        Task { @MainActor in
            await UsageViewModel.shared.refresh()
            self.reload()
            self.reposition()
        }
    }

    func hide() {
        stopMonitor()
        panel.orderOut(nil)
    }

    func reload() {
        let model = UsageViewModel.shared
        let height = content.render(
            windows: model.windows,
            statusMessage: model.statusMessage,
            updatedText: model.updatedText,
            launchAtLogin: model.launchAtLogin,
            isLoading: model.isLoading
        )
        let size = NSSize(width: 280, height: height)
        panel.setContentSize(size)
        if let container = panel.contentView {
            container.setFrameSize(size)
        }
        content.setFrameSize(size)
        reposition()
    }

    private func reposition() {
        guard panel.isVisible, let button = statusItem?.button, let window = button.window else { return }
        let buttonRect = button.convert(button.bounds, to: nil)
        let screenRect = window.convertToScreen(buttonRect)
        let size = panel.frame.size
        let x = min(
            max(8, screenRect.midX - size.width / 2),
            (NSScreen.main?.visibleFrame.maxX ?? screenRect.maxX) - size.width - 8
        )
        let y = screenRect.minY - size.height - 6
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }

    private func startMonitor() {
        stopMonitor()
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hide()
        }
    }

    private func stopMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }
}

private final class VisualContainerView: NSView {
    private let effect = NSVisualEffectView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.masksToBounds = true
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.white.withAlphaComponent(0.22).cgColor

        // Lighter frosted glass: HUD material is more transparent than .menu.
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.alphaValue = 0.82
        effect.frame = bounds
        effect.autoresizingMask = [.width, .height]
        addSubview(effect, positioned: .below, relativeTo: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class UsagePanelView: NSView {
    var onRefresh: (() -> Void)?
    var onQuit: (() -> Void)?
    var onToggleLogin: ((Bool) -> Void)?

    private let metersHost = NSView()
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let updatedLabel = NSTextField(labelWithString: "")
    private let loginSwitch = NSSwitch()
    private var meterViews: [NSView] = []
    private var actionRows: [NSView] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setupChrome()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupChrome() {
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.isHidden = true
        statusLabel.maximumNumberOfLines = 3
        addSubview(statusLabel)

        metersHost.wantsLayer = true
        addSubview(metersHost)

        updatedLabel.font = .systemFont(ofSize: 11)
        updatedLabel.textColor = .secondaryLabelColor
        updatedLabel.alignment = .center
        addSubview(updatedLabel)

        actionRows = [
            makeActionRow(title: "刷新", trailing: "⌘R", action: #selector(refreshClicked)),
            makeLoginRow(),
            makeSplitActionRow(
                leftTitle: "ChatGPT",
                leftAction: #selector(openChatGPTClicked),
                rightTitle: "Codex Resets",
                rightAction: #selector(openResetsClicked)
            ),
            makeActionRow(title: "退出", trailing: nil, action: #selector(quitClicked)),
        ]
        actionRows.forEach { addSubview($0) }
    }

    @discardableResult
    func render(
        windows: [DisplayWindow],
        statusMessage: String?,
        updatedText: String,
        launchAtLogin: Bool,
        isLoading: Bool
    ) -> CGFloat {
        meterViews.forEach { $0.removeFromSuperview() }
        meterViews.removeAll()

        let width: CGFloat = 280
        let inset: CGFloat = 14
        let contentWidth = width - inset * 2
        var y: CGFloat = inset

        if let statusMessage, windows.isEmpty {
            statusLabel.isHidden = false
            statusLabel.stringValue = statusMessage
            let statusHeight = statusLabel.sizeThatFits(
                NSSize(width: contentWidth, height: 80)
            ).height
            statusLabel.frame = NSRect(x: inset, y: 0, width: contentWidth, height: statusHeight)
            y += statusHeight + 10
        } else {
            statusLabel.isHidden = true
            statusLabel.stringValue = ""
        }

        let metersTop = y
        var metersHeight: CGFloat = 0
        for (index, window) in windows.enumerated() {
            let card = MeterCardView(window: window, emphasize: index == 0)
            let cardHeight: CGFloat = 78
            card.frame = NSRect(x: 0, y: metersHeight, width: contentWidth, height: cardHeight)
            metersHost.addSubview(card)
            meterViews.append(card)
            metersHeight += cardHeight + (index == windows.count - 1 ? 0 : 10)
        }
        metersHost.frame = NSRect(x: inset, y: metersTop, width: contentWidth, height: max(metersHeight, 1))
        y = metersTop + max(metersHeight, 0) + 10

        let dividerY = y
        y += 8

        for row in actionRows {
            row.frame = NSRect(x: inset, y: y, width: contentWidth, height: 32)
            y += 32
        }

        loginSwitch.state = launchAtLogin ? .on : .off
        updatedLabel.isHidden = true
        y += 8

        // AppKit views are bottom-up; flip by translating after measuring top-down.
        let totalHeight = y
        func flip(_ rect: NSRect) -> NSRect {
            NSRect(x: rect.origin.x, y: totalHeight - rect.origin.y - rect.height, width: rect.width, height: rect.height)
        }

        if !statusLabel.isHidden {
            statusLabel.frame = flip(statusLabel.frame)
        }
        metersHost.frame = flip(metersHost.frame)
        for row in actionRows {
            row.frame = flip(row.frame)
        }

        // Draw divider as a thin layer/view
        if let old = subviews.first(where: { $0.identifier?.rawValue == "divider" }) {
            old.removeFromSuperview()
        }
        let divider = NSBox(frame: flip(NSRect(x: inset, y: dividerY, width: contentWidth, height: 1)))
        divider.identifier = NSUserInterfaceItemIdentifier("divider")
        divider.boxType = .separator
        addSubview(divider)

        setFrameSize(NSSize(width: width, height: totalHeight))
        return totalHeight
    }

    private func makeActionRow(title: String, trailing: String?, action: Selector) -> NSView {
        let row = HoverRowView(frame: .zero)
        row.clickHandler = { [weak self] in
            guard let self else { return }
            _ = self.perform(action)
        }

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.textColor = .labelColor
        titleLabel.isEditable = false
        titleLabel.isBordered = false
        titleLabel.drawsBackground = false
        titleLabel.frame = NSRect(x: 8, y: 7, width: 160, height: 18)
        row.addSubview(titleLabel)

        if let trailing {
            let trailingLabel = NSTextField(labelWithString: trailing)
            trailingLabel.font = .systemFont(ofSize: 12)
            trailingLabel.textColor = .secondaryLabelColor
            trailingLabel.alignment = .right
            trailingLabel.isEditable = false
            trailingLabel.isBordered = false
            trailingLabel.drawsBackground = false
            trailingLabel.frame = NSRect(x: 180, y: 7, width: 64, height: 18)
            row.addSubview(trailingLabel)
        }

        return row
    }

    private func makeLoginRow() -> NSView {
        let row = HoverRowView(frame: .zero)

        let label = NSTextField(labelWithString: "登录时打开")
        label.font = .systemFont(ofSize: 13)
        label.textColor = .labelColor
        label.frame = NSRect(x: 8, y: 7, width: 160, height: 18)
        row.addSubview(label)

        loginSwitch.controlSize = .small
        loginSwitch.target = self
        loginSwitch.action = #selector(loginToggled)
        loginSwitch.frame = NSRect(x: 200, y: 5, width: 40, height: 22)
        row.addSubview(loginSwitch)

        return row
    }

    private func makeSplitActionRow(
        leftTitle: String,
        leftAction: Selector,
        rightTitle: String,
        rightAction: Selector
    ) -> NSView {
        let row = SplitActionRowView(frame: .zero)
        row.configure(
            leftTitle: leftTitle,
            rightTitle: rightTitle,
            onLeft: { [weak self] in
                guard let self else { return }
                _ = self.perform(leftAction)
            },
            onRight: { [weak self] in
                guard let self else { return }
                _ = self.perform(rightAction)
            }
        )
        return row
    }

    @objc private func refreshClicked() {
        onRefresh?()
    }

    @objc private func openChatGPTClicked() {
        openLocalChatGPT()
    }

    @objc private func openResetsClicked() {
        guard let url = URL(string: "https://codex-resets.com/") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func quitClicked() {
        onQuit?()
    }

    @objc private func loginToggled() {
        onToggleLogin?(loginSwitch.state == .on)
    }

    private func openLocalChatGPT() {
        let workspace = NSWorkspace.shared
        let candidates = [
            "com.openai.chat",
            "com.openai.chatgpt",
        ]

        for bundleID in candidates {
            if let url = workspace.urlForApplication(withBundleIdentifier: bundleID) {
                workspace.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                return
            }
        }

        let appPaths = [
            "/Applications/ChatGPT.app",
            "\(NSHomeDirectory())/Applications/ChatGPT.app",
        ]
        for path in appPaths {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path) {
                workspace.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                return
            }
        }

        // Fallback: open ChatGPT web if desktop app is missing.
        if let url = URL(string: "https://chatgpt.com/") {
            workspace.open(url)
        }
    }
}

private final class HoverRowView: NSView {
    var clickHandler: (() -> Void)?

    private var isHovered = false {
        didSet { applyHoverStyle() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.clear.cgColor
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect, .enabledDuringMouseDrag],
                owner: self,
                userInfo: nil
            )
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        NSCursor.pointingHand.set()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        NSCursor.arrow.set()
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return }
        // Don't steal clicks from the login switch.
        if let switchView = subviews.compactMap({ $0 as? NSSwitch }).first,
           switchView.frame.contains(point) {
            return
        }
        clickHandler?()
    }

    private func applyHoverStyle() {
        layer?.backgroundColor = isHovered
            ? Theme.accent.withAlphaComponent(0.14).cgColor
            : NSColor.clear.cgColor
    }

    override func layout() {
        super.layout()
        if let switchView = subviews.compactMap({ $0 as? NSSwitch }).first {
            switchView.frame.origin.x = bounds.width - switchView.frame.width - 8
        }
        if let trailing = subviews.compactMap({ $0 as? NSTextField }).last,
           trailing.stringValue == "⌘R" {
            trailing.frame.origin.x = bounds.width - trailing.frame.width - 8
        }
    }
}

private final class SplitActionRowView: NSView {
    private let leftButton = HoverRowView(frame: .zero)
    private let rightButton = HoverRowView(frame: .zero)
    private let leftLabel = NSTextField(labelWithString: "")
    private let rightLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        for label in [leftLabel, rightLabel] {
            label.font = .systemFont(ofSize: 13)
            label.textColor = .labelColor
            label.isEditable = false
            label.isBordered = false
            label.drawsBackground = false
        }
        leftLabel.alignment = .left
        rightLabel.alignment = .right

        leftButton.addSubview(leftLabel)
        rightButton.addSubview(rightLabel)
        addSubview(leftButton)
        addSubview(rightButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        leftTitle: String,
        rightTitle: String,
        onLeft: @escaping () -> Void,
        onRight: @escaping () -> Void
    ) {
        leftLabel.stringValue = leftTitle
        rightLabel.stringValue = rightTitle
        leftButton.clickHandler = onLeft
        rightButton.clickHandler = onRight
    }

    override func layout() {
        super.layout()
        let gap: CGFloat = 6
        let half = floor((bounds.width - gap) / 2)
        leftButton.frame = NSRect(x: 0, y: 0, width: half, height: bounds.height)
        rightButton.frame = NSRect(x: half + gap, y: 0, width: bounds.width - half - gap, height: bounds.height)
        leftLabel.frame = NSRect(x: 8, y: 7, width: leftButton.bounds.width - 12, height: 18)
        rightLabel.frame = NSRect(x: 4, y: 7, width: rightButton.bounds.width - 12, height: 18)
    }
}

final class MeterCardView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let percentLabel = NSTextField(labelWithString: "")
    private let resetLabel = NSTextField(labelWithString: "")
    private let progressBar: ProgressBarView

    init(window: DisplayWindow, emphasize: Bool) {
        let useAccent = emphasize || window.usedPercent >= Theme.highUsageThreshold
        progressBar = ProgressBarView(
            progress: window.usedPercent / 100,
            fillColor: useAccent ? Theme.accent : NSColor.labelColor.withAlphaComponent(0.45)
        )
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.borderWidth = 0
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.55).cgColor

        titleLabel.stringValue = window.title
        titleLabel.font = .systemFont(ofSize: 12)
        titleLabel.textColor = .secondaryLabelColor

        percentLabel.stringValue = "\(Int(window.usedPercent.rounded()))%"
        percentLabel.font = .monospacedDigitSystemFont(ofSize: 18, weight: .semibold)
        percentLabel.alignment = .right
        percentLabel.textColor = useAccent ? Theme.accent : .labelColor

        resetLabel.stringValue = window.resetText
        resetLabel.font = .systemFont(ofSize: 11)
        resetLabel.textColor = .secondaryLabelColor

        addSubview(titleLabel)
        addSubview(percentLabel)
        addSubview(progressBar)
        addSubview(resetLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let inset: CGFloat = 12
        titleLabel.frame = NSRect(x: inset, y: bounds.height - 30, width: 120, height: 18)
        percentLabel.frame = NSRect(x: bounds.width - inset - 70, y: bounds.height - 34, width: 70, height: 24)
        progressBar.frame = NSRect(x: inset, y: 28, width: bounds.width - inset * 2, height: 8)
        resetLabel.frame = NSRect(x: inset, y: 8, width: bounds.width - inset * 2, height: 14)
    }
}

final class ProgressBarView: NSView {
    private let track = NSView()
    private let fill = NSView()
    private var progress: CGFloat

    init(progress: Double, fillColor: NSColor) {
        self.progress = min(max(CGFloat(progress), 0), 1)
        super.init(frame: .zero)
        wantsLayer = true

        track.wantsLayer = true
        track.layer?.cornerRadius = 4
        track.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.28).cgColor

        fill.wantsLayer = true
        fill.layer?.cornerRadius = 4
        fill.layer?.backgroundColor = fillColor.cgColor

        addSubview(track)
        track.addSubview(fill)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        track.frame = bounds
        let width = max(4, bounds.width * progress)
        fill.frame = CGRect(x: 0, y: 0, width: width, height: bounds.height)
    }
}
