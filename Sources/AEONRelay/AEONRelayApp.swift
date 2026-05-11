import SwiftUI
import AppKit
import Combine

@main
struct AEONRelayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

// MARK: - Keyable Panel

/// NSPanel with `.nonactivatingPanel` blocks SwiftUI button events.
/// This subclass restores key-window capability so buttons, toggles,
/// text fields, and disclosure carets all work correctly.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: NSPanel!
    let configManager = ConfigManager()
    let channelListener: ChannelListener
    private var cancellable: AnyCancellable?
    private var globalMonitor: Any?
    private var localMonitor: Any?

    override init() {
        self.channelListener = ChannelListener(configManager: configManager)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Single-instance guard: quit if another copy is already running
        let dominated = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        if dominated.count > 1 {
            NSApp.terminate(nil)
            return
        }

        configManager.ensureDirectories()
        configManager.loadConfig()
        channelListener.startAll()

        // Register for app termination to clean up channels
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            Task { await self.channelListener.stopAll() }
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.action = #selector(togglePanel)
            button.target = self
            updateIcon()
        }

        let panelSize = NSSize(width: 380, height: 640)
        panel = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.nonactivatingPanel, .titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.hasShadow = true
        panel.backgroundColor = .windowBackgroundColor
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .utilityWindow

        let hostingView = NSHostingView(
            rootView: ContentView(configManager: configManager, channelListener: channelListener)
        )
        panel.contentView = hostingView

        cancellable = channelListener.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateIcon() }
        }
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        let hasConnected = channelListener.activeProviders.values.contains(true)
        let hasEnabled = configManager.channels.contains { $0.enabled }
        let name: String
        let color: NSColor

        if hasConnected {
            name = "antenna.radiowaves.left.and.right"
            color = .systemGreen
        } else if hasEnabled {
            name = "antenna.radiowaves.left.and.right"
            color = .systemOrange
        } else {
            name = "antenna.radiowaves.left.and.right.slash"
            color = .systemGray
        }
        button.image = tintedMenuBarIcon(name, color: color)

        // Badge count: active executions
        let activeCount = channelListener.activeProviders.values.filter({ $0 }).count
        if activeCount > 0 {
            button.attributedTitle = NSAttributedString(
                string: " \(activeCount)",
                attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .bold),
                    .baselineOffset: 1
                ]
            )
        } else {
            button.title = ""
        }
    }

    private func tintedMenuBarIcon(_ name: String, color: NSColor) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return NSImage() }
        let size = symbol.size
        let result = NSImage(size: size)
        result.lockFocus()
        symbol.draw(in: NSRect(origin: .zero, size: size),
                    from: .zero, operation: .sourceOver, fraction: 1.0)
        color.set()
        NSRect(origin: .zero, size: size).fill(using: .sourceAtop)
        result.unlockFocus()
        result.isTemplate = false
        return result
    }

    @objc private func togglePanel() {
        if panel.isVisible {
            closePanel()
        } else {
            positionPanelBelowStatusItem()
            panel.makeKeyAndOrderFront(nil)
            if #available(macOS 14.0, *) {
                NSApp.activate()
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }

            globalMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]
            ) { [weak self] _ in
                self?.closePanel()
            }

            localMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]
            ) { [weak self] event in
                guard let self else { return event }
                if event.window === self.panel { return event }
                if event.window === self.statusItem.button?.window { return event }
                self.closePanel()
                return event
            }
        }
    }

    private func positionPanelBelowStatusItem() {
        guard let button = statusItem.button,
              let buttonWindow = button.window else { return }
        let buttonRect = button.convert(button.bounds, to: nil)
        let screenRect = buttonWindow.convertToScreen(buttonRect)

        let panelWidth = panel.frame.width
        let panelHeight = panel.frame.height
        var x = screenRect.midX - panelWidth / 2
        let y = screenRect.minY - panelHeight - 4

        if let screen = NSScreen.main {
            let maxX = screen.visibleFrame.maxX
            let minX = screen.visibleFrame.minX
            if x + panelWidth > maxX { x = maxX - panelWidth }
            if x < minX { x = minX }
        }

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func closePanel() {
        panel.orderOut(nil)
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
    }
}
