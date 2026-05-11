# Feature: Configuration Management

## Purpose
Loads, saves, and manages all AEON Relay configuration: global settings, channel definitions, workspace profiles. Also handles update checking, dependency detection, credential storage, and activity logging.

## How It Works

### Directory Structure
```
~/.aeon-relay/
├── config.json          # GlobalConfig
├── channels/            # One JSON file per channel
│   └── *.json           # ChannelConfig
├── profiles/            # One JSON file per profile
│   └── *.json           # WorkspaceProfile
├── audit/               # JSONL audit logs
├── logs/                # Application logs
└── state.json           # Runtime state (unused currently)
```

### Data Flow
```
ensureDirectories() → seedExampleConfigs() (first run only)
loadConfig() → loadGlobalConfig() + loadChannels() + loadProfiles()
saveChannel() → encode JSON → write to channels/ → reloadChannels()
toggleChannel() → JSON mutation via JSONSerialization → write → reload
saveBotToken() → read credentials.env → replace/append → write
```

### Update System
```
checkForUpdate() → GitHub API /commits/main → compare SHA → updateState
runUpdate() → git pull --ff-only && make install (in background thread)
```

## API Surface

### Public Methods
- `ensureDirectories()` - create config folder structure
- `loadConfig()` - load all config from disk
- `profileNamed(_:) -> WorkspaceProfile?` - lookup by name
- `toggleChannel(_:enabled:)` - enable/disable a channel
- `saveChannel(_:)` - create or update channel config
- `deleteChannel(_:)` - remove channel config file
- `saveBotToken(envName:token:)` - store token in credentials.env
- `openConfigFolder()` - open ~/.aeon-relay in Finder
- `recentAuditEntries(limit:) -> [AuditEntry]` - recent executions
- `logActivity(_:)` - append to in-memory activity log
- `checkForUpdate()` - check GitHub for newer commit
- `runUpdate()` - pull and reinstall
- `refreshDependencies()` - clear dependency cache

### Published Properties
- `globalConfig: GlobalConfig`
- `channels: [ChannelConfig]`
- `profiles: [WorkspaceProfile]`
- `activityLog: [ActivityEntry]`
- `updateState: UpdateState`
- `copilotAvailable, claudeAvailable, codexAvailable: Bool`

## Models

### GlobalConfig
- `version`, `maxConcurrentExecutions`, `defaultTimeout`, `rateLimitPerMinute`
- `progressUpdateInterval`, `firstProgressDelay`, `logLevel`, `auditRetentionDays`
- `voiceOnCompletion`, `notificationsEnabled`

### ChannelConfig
- `name`, `provider`, `botToken`, `enabled`, `allowFrom`, `defaultProfile`
- `profileRouting`, `greeting`, `showTyping`, `maxMessageLength`

### WorkspaceProfile
- `name`, `description`, `workdir`, `agent`, `model`, `backend`, `timeout`, `env`

### ExecutionBackend
- `.copilot`, `.claude`, `.codex`, `.custom`

## Dependencies
- `Foundation`, `AppKit` (for `NSWorkspace.shared.open`)
- Reads from `~/.config/aeon/credentials.env` for GitHub PAT and bot tokens

## Known Limitations
- `maxConcurrentExecutions` is defined but never enforced in ChannelListener
- `progressUpdateInterval` and `firstProgressDelay` are configured but unused
- `auditRetentionDays` is configured but no cleanup routine exists
- `state.json` is mentioned in README but never read or written
- Update check compares 7-char SHA, which can collide (extremely rare)
- `runUpdate()` runs `git pull --ff-only && make install` which relaunches the app, but the old process doesn't terminate itself
- Token resolution only supports `env:VAR_NAME` format or literal tokens
- No config validation on load (malformed JSON silently returns defaults/empty arrays)

## Test Coverage
4 tests: GlobalConfig defaults, ChannelConfig decoding, WorkspaceProfile decoding, ExecutionBackend values. No tests for load/save/seed/toggle/delete/update logic.
