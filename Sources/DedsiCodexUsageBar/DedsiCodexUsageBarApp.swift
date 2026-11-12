import AppKit

@main
enum DedsiCodexUsageBarMain {
    private static var retainedDelegate: AppDelegate?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        retainedDelegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let popoverController = UsagePopoverController()
    private var refreshMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        if let button = item.button {
            button.title = "C —"
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popoverController.attach(to: item)

        UsageViewModel.shared.onChange = { [weak self] in
            self?.updateStatusTitle()
            self?.popoverController.reload()
        }
        UsageViewModel.shared.start()
        updateStatusTitle()

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains(.command),
               event.charactersIgnoringModifiers?.lowercased() == "r" {
                self?.refresh()
                return nil
            }
            return event
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        popoverController.toggle()
    }

    @objc private func refresh() {
        Task { @MainActor in
            await UsageViewModel.shared.refresh()
        }
    }

    private func updateStatusTitle() {
        statusItem?.button?.title = UsageViewModel.shared.menuBarTitle
    }
}
