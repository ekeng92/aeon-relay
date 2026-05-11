# AEON Relay — Feature Inventory

> Audit date: 2026-05-10
> Repo: aeon-relay (~/Projects/aeon-relay)
> Stack: Swift 5.9, macOS 13+, SwiftUI, zero external dependencies
> Total source: 2,670 lines across 12 Swift files + 3 test files (178 test lines)

## Features by Layer

### Core Application

| # | Feature | Primary Files | Test Files | Doc Status |
|---|---------|---------------|------------|------------|
| 1 | **App Lifecycle & Menu Bar** | `AEONRelayApp.swift` (170L) | none | README only |
| 2 | **Configuration Management** | `ConfigManager.swift` (522L) | `ConfigManagerTests.swift` (62L) | copilot-instructions |
| 3 | **Channel Listener & Message Routing** | `ChannelListener.swift` (345L) | none | copilot-instructions |
| 4 | **Telegram Provider** | `TelegramProvider.swift` (209L), `MessageProvider.swift` (25L) | none | copilot-instructions |
| 5 | **Execution Engine** | `ExecutionEngine.swift` (157L) | none | copilot-instructions |
| 6 | **Security Manager** | `SecurityManager.swift` (42L) | `SecurityManagerTests.swift` (77L) | copilot-instructions |
| 7 | **Audit Logger** | `AuditLogger.swift` (80L) | `AuditLoggerTests.swift` (39L) | copilot-instructions |
| 8 | **Reply Sender** | `ReplySender.swift` (45L) | none | copilot-instructions |
| 9 | **Build Info** | `BuildInfo.swift` (5L) | none | none |

### UI Layer

| # | Feature | Primary Files | Test Files | Doc Status |
|---|---------|---------------|------------|------------|
| 10 | **ContentView (Menu Bar Popover)** | `ContentView.swift` (873L) | none | none |

### Installation & Scripts

| # | Feature | Primary Files | Test Files | Doc Status |
|---|---------|---------------|------------|------------|
| 11 | **Local Install** | `scripts/install.sh`, `Makefile` | none | README |
| 12 | **Remote Install** | `scripts/remote-install.sh` | none | README |
| 13 | **Uninstall** | `scripts/uninstall.sh`, `Makefile` | none | README |

### Configuration & Examples

| # | Feature | Primary Files | Test Files | Doc Status |
|---|---------|---------------|------------|------------|
| 14 | **Example Configs** | `examples/channel-telegram.json`, `examples/profile-example.json` | none | README |

## Functional Feature Groups

### F1: Telegram Integration
- Long polling (no webhook, works behind NAT)
- Bot token validation via `getMe`
- Typing indicators
- Message parsing (text only)
- Sender allowlist security
- Rate limiting
- Greeting on connect

### F2: CLI Execution
- Copilot CLI, Claude CLI, Codex CLI, custom commands
- Workspace profiles with per-profile env vars
- Configurable timeout with forced kill
- Git diff/summary capture post-execution
- Reply formatting with truncation

### F3: Slash Commands
- `/help`, `/status`, `/profiles`, `/use <name>`, `/history`, `/cancel`
- Profile switching per channel (in-memory override)

### F4: Configuration System
- Global config (`config.json`), channels (`channels/*.json`), profiles (`profiles/*.json`)
- Example seeding on first run
- Hot-reload via `reloadConfig()`
- Channel CRUD (add/edit/delete from UI)
- Bot token storage in `~/.config/aeon/credentials.env`

### F5: Menu Bar UI
- Status card with connection indicators
- Channel list with toggle, expand, edit, delete
- Channel editor (add/edit with token and chat ID)
- Recent executions list
- Profile list with expand/detail
- Quick actions (Open Config, Open Audit, Start/Stop All, Reload)
- Update checker (compare Git SHA)
- Activity log
- Dependency indicators (copilot, claude, codex availability)
- Click-outside-to-close panel behavior

### F6: Audit System
- JSONL per-day files in `~/.aeon-relay/audit/`
- Full execution metadata (prompt, duration, exit code, files changed, git diff)
- Recent entries query for UI

### F7: Update System
- GitHub API check against main branch HEAD
- PAT auth for private repos
- In-app update via `git pull && make install`

## Test Coverage Summary

| Component | Test File | Tests | Coverage Assessment |
|-----------|-----------|-------|--------------------|
| AuditLogger | AuditLoggerTests.swift | 1 test (encode/decode roundtrip) | Minimal: no file I/O tests |
| ConfigManager | ConfigManagerTests.swift | 4 tests (defaults, decoding) | Minimal: no load/save/seed tests |
| SecurityManager | SecurityManagerTests.swift | 4 tests (auth, rate limit) | Decent: core auth + rate limit |
| TelegramProvider | none | 0 | No coverage |
| ExecutionEngine | none | 0 | No coverage |
| ChannelListener | none | 0 | No coverage |
| ReplySender | none | 0 | No coverage |
| ContentView | none | 0 | No coverage (UI) |

**Total: 9 tests across 3 files. 5 of 10 source components have zero test coverage.**
