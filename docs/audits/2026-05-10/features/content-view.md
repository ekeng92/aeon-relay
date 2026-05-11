# Feature: Menu Bar UI (ContentView)

## Purpose
SwiftUI popover view for the AEON Relay menu bar app. Displays connection status, channels with CRUD, recent executions, profiles, quick actions, update checking, and activity log.

## How It Works

### UI Sections (top to bottom)
1. **Status Card** - connection status icon, title, subtitle, dependency indicators
2. **Channels** - list with toggle, expand/collapse, edit/delete, add new
3. **Channel Editor** - inline form for creating/editing channels (name, token, chat ID)
4. **Recent Executions** - last 5 audit entries with status, prompt preview, duration
5. **Profiles** - expandable list showing workdir, backend, model, timeout
6. **Quick Actions** - Open Config, Open Audit, Start/Stop All, Reload
7. **Update** - check for updates, install, version display
8. **Activity** - scrolling log of recent events
9. **Quit** - terminate app

### Channel Editor Flow
```
Add Channel:
  → user fills name, bot token, chat ID
  → saveChannelFromEditor() validates name uniqueness
  → generates env var name: RELAY_<NAME>_TOKEN
  → saves token to ~/.config/aeon/credentials.env
  → saves channel JSON to ~/.aeon-relay/channels/
  → auto-enables and starts the channel

Edit Channel:
  → pre-fills name and chat ID from existing
  → token field blank (leave blank to keep current)
  → same save flow
```

## API Surface
- `ContentView(configManager:channelListener:)` - main view constructor
- Internal state: `expandedChannel`, `expandedProfile`, `editingChannel`, `isAddingChannel`, `tokenInput`, `chatIDInput`, `channelNameInput`, `showDeleteConfirm`, `editorError`

## Dependencies
- `ConfigManager` (observed)
- `ChannelListener` (observed)
- SwiftUI framework

## Known Limitations
- Fixed frame size (380x640), no resizing
- No profile editor (profiles must be edited as JSON files)
- Channel editor only supports Telegram (hardcoded `provider: "telegram"`)
- No input validation on chat ID format (should be numeric)
- Delete confirmation is inline, not a modal (could be accidentally dismissed)
- No pagination on recent executions or activity log
- No search/filter on any list
- No dark/light mode override (follows system)
- Dependency check runs synchronously on first access (could block UI briefly)

## Test Coverage
**None.** UI components are not unit-tested.
