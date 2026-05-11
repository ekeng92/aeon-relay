# Feature: Channel Listener & Message Routing

## Purpose
Central coordinator that manages provider lifecycle, routes incoming messages through security checks, resolves workspace profiles, dispatches to the execution engine, and sends formatted replies back through the originating channel.

## How It Works

```
startAll() → for each enabled channel → startChannel()
  → resolve bot token (env: or literal)
  → create TelegramProvider with onMessage callback
  → set onStatusChange callback for UI updates
  → provider.start() (async)

handleMessage() flow:
  incoming message
  → SecurityManager.authorize() (allowlist check)
  → SecurityManager.checkRateLimit()
  → if slash command → handleSlashCommand()
  → else → resolveProfile() → send typing indicator → execute() → formatReply() → sendReply() → auditLog()
```

### Profile Resolution Priority
1. Per-channel override from `/use` command (in-memory `channelProfileOverrides`)
2. Profile routing prefixes from channel config (`profileRouting`)
3. Channel's `defaultProfile`

### Slash Commands
| Command | Action |
|---------|--------|
| `/help` | List commands |
| `/status` | Show active profile details |
| `/profiles` | List all profiles |
| `/use <name>` | Switch active profile for this channel |
| `/history` | Show last 5 audit entries |
| `/cancel` | Cancel running executions |

## API Surface
- `startAll()` - start all enabled channels
- `stopAll()` - stop all providers
- `toggleChannel(_:enabled:)` - enable/disable with auto start/stop
- `reloadConfig()` - stop all, reload config, restart

### Published Properties
- `activeProviders: [String: Bool]` - connection status per channel
- `channelErrors: [String: String]` - error messages per channel
- `channelBots: [String: String]` - bot usernames per channel

## Dependencies
- `ConfigManager` (injected)
- `ExecutionEngine` (owned)
- `AuditLogger` (owned)
- `ReplySender` (owned)
- `SecurityManager` (owned)
- `TelegramProvider` (created per channel)

## Known Limitations
- `runningExecutions` and `runningTasks` are tracked but `/cancel` only calls `task.cancel()`, which won't terminate a running `Process` (the execution engine's process will continue)
- `executionQueue` is declared but never used (queueing not implemented)
- `maxConcurrentExecutions` from GlobalConfig is never checked before dispatching
- Profile overrides via `/use` are lost on reload
- No mutex/actor isolation for `securityManager` (struct with mutable state accessed from multiple async contexts)
- Greeting is sent to all `allowFrom` chat IDs, even if they haven't messaged the bot
- Error messages from execution failures are sent raw to the user
- Token resolution is duplicated between ChannelListener and ConfigManager

## Test Coverage
**None.** This is the most complex orchestration component with zero tests.
