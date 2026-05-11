# Feature: App Lifecycle & Menu Bar

## Purpose
Entry point for the AEON Relay macOS menu bar application. Manages the NSStatusItem, floating panel, and click-outside-to-close behavior.

## How It Works

```
App Launch → AppDelegate.applicationDidFinishLaunching
  → configManager.ensureDirectories()
  → configManager.loadConfig()
  → channelListener.startAll()
  → Create NSStatusItem with antenna icon
  → Create NSPanel with ContentView (SwiftUI)
  → Subscribe to channelListener changes for icon updates
```

### Menu Bar Icon States
- Green antenna: at least one channel connected
- Orange antenna: channels enabled but not yet connected
- Gray slashed antenna: no channels enabled
- Badge count: number of active connections

### Panel Behavior
- Positioned below status bar item
- Floating panel level, non-activating
- Click outside (global + local event monitors) closes panel
- Panel remembers nothing between open/close cycles

## API Surface
- `AEONRelayApp` (SwiftUI `App` struct, uses `@NSApplicationDelegateAdaptor`)
- `AppDelegate`: manages `statusItem`, `panel`, `configManager`, `channelListener`
- `togglePanel()`: opens/closes the popover
- `updateIcon()`: refreshes status bar icon based on connection state

## Dependencies
- `ConfigManager` (owned, created here)
- `ChannelListener` (owned, created here)
- `ContentView` (SwiftUI view, injected with configManager + channelListener)
- `Combine` (for `objectWillChange` subscription)

## Configuration
None directly. All config flows through `ConfigManager`.

## Known Limitations
- Panel size is fixed at 380x640
- No auto-start on login (no LaunchAgent)
- Icon tinting uses manual `NSImage` composition (no SF Symbol tinting API on macOS 13)
- `hidesOnDeactivate` is false, which means panel stays visible when app loses focus (intentional for utility panels, but may surprise users)

## Test Coverage
**None.** App lifecycle and UI integration are not unit-tested.
