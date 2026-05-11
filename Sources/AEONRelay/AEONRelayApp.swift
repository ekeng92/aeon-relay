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

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: NSPanel!
    let configManager = ConfigManager()
    private var cancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configManager.ensureDirectories()
        configManager.loadConfig()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.action = #selector(togglePanel)
            button.target = self
            updateIcon()
        }

        let panelSize = NSSize(width: 380, height: 520)
        panel = NSPanel(
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
        panel.hidesOnDeactivate = true
        panel.animationBehavior = .utilityWindow

        let hostingView = NSHostingView(rootView: ContentView(configManager: configManager))
        panel.contentView = hostingView

        cancellable = configManager.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateIcon() }
        }
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        let connected = configManager.channels.contains { $0.enabled }
        let name = connected ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash"
        let color: NSColor = connected ? .systemGreen : .systemGray
        button.image = tintedMenuBarIcon(name, color: color)
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
            panel.orderOut(nil)
            return
        }

        guard let button = statusItem.button else { return }
        let buttonFrame = button.window?.convertToScreen(button.frame) ?? .zero
        let panelSize = panel.frame.size

        let x = buttonFrame.midX - panelSize.width / 2
        let y = buttonFrame.minY - panelSize.height - 4

        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
