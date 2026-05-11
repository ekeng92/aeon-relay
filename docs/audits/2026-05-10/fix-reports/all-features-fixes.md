# Fix Report — All Features

> Audit date: 2026-05-10
> All fixes applied in a single pass across the codebase

## Critical Fixes

### C1: Command Injection via Custom Backend (FIXED)
**File**: `Sources/AEONRelay/ExecutionEngine.swift`
**Change**: Custom backend now sanitizes input by splitting on whitespace and rejecting any component containing shell metacharacters (`;|&$\`(){}[]!#~<>\\\"'`). Invalid commands produce an echo error message instead of executing.
**Before**: Raw prompt passed as shell command
**After**: Metacharacter validation with blocklist

### C2: Data Race on SecurityManager (FIXED)
**File**: `Sources/AEONRelay/SecurityManager.swift`
**Change**: Converted `SecurityManager` from `struct` to `actor`. All callers now use `await` for thread-safe access to `messageTimestamps`.
**Files also changed**: `ChannelListener.swift` (added `await`), `SecurityManagerTests.swift` (converted tests to `async`)

## High Fixes

### H1: No Message Length Validation (FIXED)
**File**: `Sources/AEONRelay/Providers/TelegramProvider.swift`
**Change**: `sendReply` now splits messages exceeding 4096 characters at newline boundaries, sending multiple messages sequentially.

### H2: Timeout Doesn't Kill Child Processes (FIXED)
**File**: `Sources/AEONRelay/ExecutionEngine.swift`
**Change**: Timeout now uses `kill(-pid, SIGTERM)` followed by `kill(-pid, SIGKILL)` to terminate the entire process group, cleaning up child processes spawned by CLI tools.

### H3: Pipe Deadlock on Large Output (FIXED)
**File**: `Sources/AEONRelay/ExecutionEngine.swift`
**Change**: stdout and stderr are now read in `Task.detached` blocks concurrently with `waitUntilExit()`, preventing buffer-full deadlocks.

### H4: maxConcurrentExecutions Never Enforced (FIXED)
**File**: `Sources/AEONRelay/ChannelListener.swift`
**Change**: Added `activeExecutionCount` tracking with guard check against `configManager.globalConfig.maxConcurrentExecutions` before dispatching. Returns user-friendly "busy" message when limit reached.
**Also**: Removed unused `executionQueue` field (M8).

### H5: Raw Error Messages Sent to User (FIXED)
**File**: `Sources/AEONRelay/ChannelListener.swift`
**Change**: Error handler now sends generic "Execution failed. Check the audit log for details." instead of `error.localizedDescription`. Full error still logged via `logger.error()`.

### H6: Prompt Escaping Improved (FIXED)
**File**: `Sources/AEONRelay/ExecutionEngine.swift`
**Change**: Prompt is now properly wrapped in single quotes (`'prompt'`) with internal single-quote escaping. Method renamed from `buildCommand` to `buildArguments` for clarity. Custom backend uses strict sanitization instead of pass-through.

## Medium Fixes

### M1: Audit Retention Cleanup (FIXED)
**File**: `Sources/AEONRelay/ConfigManager.swift`
**Change**: Added `cleanupAuditFiles()` called on app launch. Removes JSONL files older than `auditRetentionDays` (default 90).

### M3: Config Decode Errors Now Logged (FIXED)
**File**: `Sources/AEONRelay/ConfigManager.swift`
**Change**: `loadJSONFiles` now logs decode errors with the filename instead of silently dropping malformed configs.

### M5: Graceful Shutdown (FIXED)
**File**: `Sources/AEONRelay/AEONRelayApp.swift`
**Change**: Added `NSApplication.willTerminateNotification` observer in `applicationDidFinishLaunching` to stop all channels cleanly on quit.

### M8: Removed Dead Code (FIXED)
**File**: `Sources/AEONRelay/ChannelListener.swift`
**Change**: Removed unused `executionQueue` field.

**File**: `Sources/AEONRelay/ConfigManager.swift`
**Change**: Removed unused `GlobalConfig` fields: `progressUpdateInterval`, `firstProgressDelay`, `voiceOnCompletion`, `notificationsEnabled` (L6, L7).

## Deferred Items

### M2: resolveToken Duplicated
Deferred. Low risk, consolidation is a refactor that doesn't affect behavior.

### M4: TelegramProvider Uses JSONSerialization
Deferred. Works correctly, Codable migration is a style improvement.

### M6: /cancel Doesn't Kill Running Processes
Deferred. Requires ExecutionEngine API changes for process handle tracking.

### M7: Test Coverage Gaps
Partially addressed (SecurityManager tests updated for actor). Full coverage expansion requires Xcode installation for XCTest.

### M9: Update System Assumes Local Clone
Deferred. Low priority, only affects remote-install users who don't clone locally.

## Build Verification

- `swift build -c release`: ✅ 0 errors, pre-existing Sendable warnings only
- `swift test`: Cannot run (CommandLineTools only, no XCTest SDK). Tests compile in the build target
- `make build`: ✅ passes
