# Feature: Execution Engine

## Purpose
Spawns CLI processes (Copilot, Claude, Codex, or custom commands) in a specified working directory, captures stdout/stderr, enforces timeouts, and collects git diff summaries after execution.

## How It Works

```
execute(prompt, profile) →
  → buildCommand() based on backend type
  → spawn Process via /bin/zsh -l -c
  → set working directory, environment
  → pipe stdout + stderr
  → start timeout task (kills process after N seconds)
  → waitUntilExit()
  → read stdout/stderr
  → getGitSummary() + getChangedFiles() via git commands
  → return ExecutionResult
```

### Backend Command Templates
| Backend | Command Pattern |
|---------|----------------|
| copilot | `copilot [-a agent] [-m model] 'prompt'` |
| claude | `claude --print [--model model] 'prompt'` |
| codex | `codex exec 'prompt'` |
| custom | `prompt` (raw, user provides full command) |

## API Surface
- `execute(prompt:profile:) async throws -> ExecutionResult`

### ExecutionResult
- `id` - unique ID (timestamp + random hex)
- `exitCode` - process termination status
- `stdout`, `stderr` - captured output
- `duration` - wall clock seconds
- `filesChanged` - git diff --name-only
- `gitSummary` - git diff --stat
- `truncated` - always false (truncation not implemented here)

## Dependencies
- `Foundation` (Process, Pipe)
- `os` (Logger)
- `/bin/zsh` (shell)
- `/usr/bin/git` (for diff summaries)

## Configuration
- Timeout from profile (`profile.timeout`, default 300s)
- Environment variables from profile (`profile.env`)

## Known Limitations
- Shell injection risk: prompt is escaped for single quotes only (`'` → `'\''`), but custom backend passes the entire prompt as the command, allowing arbitrary command execution
- `zsh -l -c` loads login profile, which means PATH, NVM, etc. are available but adds startup overhead
- Timeout kills with `terminate()` then `interrupt()`, but doesn't clean up child processes spawned by the CLI tool
- Git summary runs against `HEAD`, which may not reflect the actual changes if the CLI tool committed
- `readDataToEndOfFile()` blocks until pipe closes, which could deadlock with large output if both stdout and stderr buffers fill
- No output streaming; entire output is buffered in memory
- `truncated` field is always false (truncation happens in ReplySender, not here)

## Test Coverage
**None.** No tests for command building, process execution, timeout handling, or git summary collection.
