# AEON Relay — Copilot Instructions

## What This Repo Is

Native macOS menu bar app that bridges messaging channels (Telegram, Discord, Slack) to Copilot CLI execution on the local machine. Send a message from your phone, get AI agent work done in your workspace, receive the result back in the chat.

## Architecture

| Component | Role |
|-----------|------|
| `ChannelListener` | Manages provider connections, routes messages to execution |
| `TelegramProvider` | Telegram Bot API long polling, implements `MessageProvider` protocol |
| `ExecutionEngine` | Spawns CLI processes (copilot/claude/codex), captures output |
| `ReplySender` | Formats execution results for channel reply |
| `SecurityManager` | Sender allowlist, rate limiting, channel enable/disable |
| `AuditLogger` | JSONL audit trail per day in `~/.aeon-relay/audit/` |
| `ConfigManager` | Loads/saves JSON configs from `~/.aeon-relay/` |
| `ContentView` | SwiftUI popover menu bar UI |

## Stack

- Swift 5.9, macOS 13+, SwiftUI
- Zero external dependencies (Foundation + SwiftUI only)
- Swift Package Manager for builds
- `Process` for CLI execution, `URLSession` for HTTP

## Conventions

- `OSLog` for logging (subsystem: `com.aeon.relay`)
- `Codable` for all JSON models
- `@MainActor` for UI-bound state
- `async/await` for networking
- Config lives in `~/.aeon-relay/` (channels/, profiles/, audit/, logs/)
- JSONL audit format, one file per day
- Sender allowlist security (silent deny for unauthorized)

## Design Docs

Full product brief: `chatkey/docs/aeon-relay/PRODUCT-BRIEF.md`
Full architecture: `chatkey/docs/aeon-relay/ARCHITECTURE.md`
Development plan: `chatkey/docs/aeon-relay/DEVELOPMENT-PLAN.md`
