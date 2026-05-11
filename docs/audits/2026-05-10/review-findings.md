# Review Findings — AEON Relay

> Audit date: 2026-05-10
> Reviewer: AEON Prime (Deep Repo Audit)

## Summary

| Severity | Count |
|----------|-------|
| 🔴 Critical | 2 |
| 🟠 High | 6 |
| 🟡 Medium | 9 |
| 🟢 Low | 7 |
| **Total** | **24** |

---

## 🔴 Critical Findings

### C1: Command Injection via Custom Backend
**File**: [ExecutionEngine.swift](../../Sources/AEONRelay/ExecutionEngine.swift#L100-L102)
**Description**: When `backend == .custom`, the prompt is passed directly as the shell command with only single-quote escaping. An attacker who gains access to an allowed Telegram account can execute arbitrary shell commands.
```swift
case .custom:
    return [escapedPrompt] // custom commands handle their own structure
```
The `escapedPrompt` only handles single quotes. Backticks, `$()`, semicolons, pipes, and other shell metacharacters are not escaped. Since this runs via `zsh -l -c`, full shell interpretation applies.
**Impact**: Remote code execution on the host machine via any allowed Telegram sender.
**Fix**: Either remove the `.custom` backend, or run custom commands with explicit arg parsing (not shell interpretation), or add a strict validation allowlist for custom commands.

### C2: Data Race on SecurityManager
**File**: [ChannelListener.swift](../../Sources/AEONRelay/ChannelListener.swift#L16), [SecurityManager.swift](../../Sources/AEONRelay/SecurityManager.swift)
**Description**: `SecurityManager` is a `struct` with `mutating func checkRateLimit()`. It is stored as `private var securityManager` on `ChannelListener` (a class). Multiple async `handleMessage()` calls access it concurrently from different Task contexts without synchronization.
**Impact**: Data race on `messageTimestamps` dictionary. Could crash the app or bypass rate limiting under concurrent load.
**Fix**: Make `SecurityManager` a class with an actor or use a lock for `messageTimestamps` access.

---

## 🟠 High Findings

### H1: No Message Length Validation Before Telegram Send
**File**: [TelegramProvider.swift](../../Sources/AEONRelay/Providers/TelegramProvider.swift#L42-L56)
**Description**: `sendReply` sends messages without checking length. Telegram's limit is 4096 characters. While `ReplySender.formatReply` truncates, the `/help`, `/status`, `/profiles` replies in `ChannelListener` are constructed without truncation.
**Impact**: Telegram API rejects oversized messages silently, user gets no response.
**Fix**: Add length validation in `sendReply` or the provider, splitting long messages into chunks.

### H2: Execution Timeout Doesn't Kill Child Processes
**File**: [ExecutionEngine.swift](../../Sources/AEONRelay/ExecutionEngine.swift#L46-L53)
**Description**: Timeout calls `process.terminate()` then `process.interrupt()`, but `copilot` CLI spawns child processes (Node.js, etc.) that are not terminated. Process groups are not used.
**Impact**: Zombie processes accumulate after timeouts, consuming system resources.
**Fix**: Set `process.qualityOfService` and use `kill(-pid, SIGTERM)` to kill the entire process group.

### H3: Potential Pipe Deadlock on Large Output
**File**: [ExecutionEngine.swift](../../Sources/AEONRelay/ExecutionEngine.swift#L55-L58)
**Description**: `process.waitUntilExit()` is called before `readDataToEndOfFile()` on both pipes. If the process writes enough data to fill the pipe buffer (64KB on macOS), the process blocks waiting for the pipe to drain, but the reader is waiting for the process to exit.
**Impact**: Execution hangs indefinitely for commands with large output.
**Fix**: Read from pipes in concurrent tasks before calling `waitUntilExit()`, or use dispatch IO.

### H4: maxConcurrentExecutions Never Enforced
**File**: [ConfigManager.swift](../../Sources/AEONRelay/ConfigManager.swift#L452) (defined), [ChannelListener.swift](../../Sources/AEONRelay/ChannelListener.swift) (not checked)
**Description**: `GlobalConfig.maxConcurrentExecutions` defaults to 3 but is never checked before dispatching executions. `runningExecutions` set and `executionQueue` array are declared but unused for queueing.
**Impact**: Unlimited concurrent CLI processes can be spawned, exhausting system resources.
**Fix**: Implement a semaphore or queue check in `handleMessage` before calling `execute()`.

### H5: Raw Error Messages Sent to User
**File**: [ChannelListener.swift](../../Sources/AEONRelay/ChannelListener.swift#L196)
**Description**: Execution failures send `error.localizedDescription` directly to the Telegram user:
```swift
await sendReply("Execution failed: \(error.localizedDescription)", to: message, channel: channel)
```
**Impact**: Internal error details (file paths, system state) leaked to the messaging channel.
**Fix**: Map errors to user-friendly messages, log full details internally.

### H6: ExecutionEngine Prompt Escaping Insufficient
**File**: [ExecutionEngine.swift](../../Sources/AEONRelay/ExecutionEngine.swift#L88)
**Description**: Prompt escaping only handles single quotes: `prompt.replacingOccurrences(of: "'", with: "'\\''")`. The escaped prompt is then wrapped in single quotes for the shell. However, this relies on the shell correctly interpreting the `'\''` pattern. If any backend command template doesn't single-quote the prompt (e.g., custom), shell metacharacters are interpreted.
**Impact**: Even for non-custom backends, if the command template changes or a new backend is added without single-quoting, injection becomes possible.
**Fix**: Use `Process.arguments` array instead of shell string concatenation to avoid shell interpretation entirely.

---

## 🟡 Medium Findings

### M1: No Audit Retention Cleanup
**File**: [ConfigManager.swift](../../Sources/AEONRelay/ConfigManager.swift#L454)
**Description**: `auditRetentionDays` is configured (default 90) but no cleanup routine exists. Audit files grow indefinitely.
**Fix**: Add periodic cleanup on app launch or config reload.

### M2: resolveToken Duplicated
**File**: [ChannelListener.swift](../../Sources/AEONRelay/ChannelListener.swift#L310-L335) and [ConfigManager.swift](../../Sources/AEONRelay/ConfigManager.swift) (similar pattern in `loadGitHubPAT`)
**Description**: Token resolution from `credentials.env` is implemented twice with slightly different logic.
**Fix**: Consolidate into a single utility method on ConfigManager.

### M3: No Config Validation on Load
**File**: [ConfigManager.swift](../../Sources/AEONRelay/ConfigManager.swift#L43-L50)
**Description**: `loadJSONFiles` silently swallows decode errors via `compactMap`. Malformed channel or profile configs are silently dropped.
**Fix**: Log decode errors so users know when a config file is malformed.

### M4: TelegramProvider Uses JSONSerialization Instead of Codable
**File**: [TelegramProvider.swift](../../Sources/AEONRelay/Providers/TelegramProvider.swift)
**Description**: All Telegram API responses are parsed via `JSONSerialization` with manual dictionary casting, while the rest of the codebase uses `Codable`. Inconsistent and error-prone.
**Fix**: Define Codable models for Telegram API responses.

### M5: No Graceful Shutdown
**File**: [AEONRelayApp.swift](../../Sources/AEONRelay/AEONRelayApp.swift)
**Description**: No `applicationWillTerminate` handler. Channels are not stopped cleanly on quit. Long-polling connections may hang.
**Fix**: Add `applicationWillTerminate` to stop all channels.

### M6: /cancel Doesn't Kill Running Processes
**File**: [ChannelListener.swift](../../Sources/AEONRelay/ChannelListener.swift#L256-L264)
**Description**: `/cancel` cancels Swift Tasks but doesn't terminate the underlying `Process` objects managed by `ExecutionEngine`. The CLI processes continue running.
**Fix**: ExecutionEngine needs a cancel/terminate API, and ChannelListener needs to track active Process references.

### M7: Test Coverage Gaps
**Description**: 5 of 10 source components have zero tests. Total test count is 9 across 3 files.
**Fix**: Add tests for ReplySender, ExecutionEngine command building, and ChannelListener message routing (at minimum).

### M8: Unused executionQueue Field
**File**: [ChannelListener.swift](../../Sources/AEONRelay/ChannelListener.swift#L22)
**Description**: `executionQueue` is declared but never used. Dead code.
**Fix**: Remove or implement queueing.

### M9: Update System Relies on Git Clone Existing Locally
**File**: [ConfigManager.swift](../../Sources/AEONRelay/ConfigManager.swift#L346-L362)
**Description**: `runUpdate()` assumes the repo exists at `~/Projects/aeon-relay`. For remote-install users, this path won't exist. The update will fail silently.
**Fix**: Fall back to a fresh clone if the local repo doesn't exist, or use the remote-install script.

---

## 🟢 Low Findings

### L1: Fixed Panel Size
**File**: [ContentView.swift](../../Sources/AEONRelay/ContentView.swift#L63)
**Description**: Panel is fixed at 380x640. No resizing support.

### L2: No LaunchAgent for Auto-Start
**Description**: App doesn't auto-start on login. Users must open it manually.

### L3: state.json Referenced in README but Unused
**File**: README.md
**Description**: `state.json` is listed in the config structure but never created or read.

### L4: connectionAttempts Never Used
**File**: [TelegramProvider.swift](../../Sources/AEONRelay/Providers/TelegramProvider.swift#L12)
**Description**: `connectionAttempts` is incremented but never read for backoff or display.

### L5: No Chat ID Format Validation in Channel Editor
**File**: [ContentView.swift](../../Sources/AEONRelay/ContentView.swift)
**Description**: Chat ID input accepts any string. Should validate as numeric.

### L6: progressUpdateInterval and firstProgressDelay Unused
**File**: [ConfigManager.swift](../../Sources/AEONRelay/ConfigManager.swift#L449-L450)
**Description**: Configured but never referenced. Dead config fields.

### L7: voiceOnCompletion and notificationsEnabled Unused
**File**: [ConfigManager.swift](../../Sources/AEONRelay/ConfigManager.swift#L455-L456)
**Description**: Configured but never referenced. Dead config fields.

---

## Cross-Cutting Issues

1. **Thread safety**: Multiple components lack proper concurrency protection. SecurityManager has a data race, ChannelListener accesses mutable state from async contexts.
2. **Error handling**: Raw errors leak to users in multiple places. No consistent error mapping.
3. **Dead code/config**: Several fields are defined but never used (executionQueue, progressUpdateInterval, voiceOnCompletion, etc.).
4. **Test deficit**: 9 tests for 2,670 lines of code. Core components (ChannelListener, ExecutionEngine, TelegramProvider) have zero coverage.

## Prioritized Fix List

1. **C1**: Command injection via custom backend (security, RCE)
2. **C2**: Data race on SecurityManager (crash risk)
3. **H3**: Pipe deadlock on large output (reliability)
4. **H6 + H5**: Prompt escaping + raw error exposure (security)
5. **H2**: Timeout doesn't kill child processes (resource leak)
6. **H4**: Concurrency limit not enforced (resource exhaustion)
7. **H1**: Message length validation (functionality)
8. **M5**: Graceful shutdown (reliability)
9. **M7**: Test coverage (quality)
