# Feature: Audit Logger

## Purpose
Writes JSONL audit entries (one per execution) to daily files in `~/.aeon-relay/audit/`. Supports reading entries back for the UI's recent executions list.

## How It Works

```
log(entry) →
  → encode to JSON via JSONEncoder (ISO 8601 dates)
  → append newline
  → if file exists: open, seek to end, write, close
  → else: write as new file

loadEntries(date) →
  → read YYYY-MM-DD.jsonl
  → split by newline, decode each line
  → return [AuditEntry]
```

## API Surface
- `log(_:)` - write a single audit entry
- `loadEntries(date:) -> [AuditEntry]` - read entries for a given date

### AuditEntry (Codable)
- `id`, `timestamp`, `channel`, `profile`, `senderID`, `prompt`
- `backend`, `agent`, `model`, `workdir`
- `duration`, `exitCode`, `filesChanged`, `gitDiff`
- `replyLength`, `replyTruncated`, `error`

## Dependencies
- `Foundation` (FileManager, FileHandle, JSONEncoder/Decoder)
- `os` (Logger)

## Configuration
- Audit directory: `~/.aeon-relay/audit/`
- File naming: `YYYY-MM-DD.jsonl`

## Known Limitations
- No file locking; concurrent writes from multiple executions could interleave JSON lines (unlikely with current sequential execution but possible if concurrency is added)
- No audit retention/cleanup (configured `auditRetentionDays` in GlobalConfig is never used)
- `loadEntries` only reads one day at a time
- No error recovery if JSONL file becomes corrupted (partial lines from crash)
- FileHandle operations use synchronous I/O on the calling thread
- No size limits on individual audit files

## Test Coverage
1 test: encode/decode roundtrip for AuditEntry. No tests for file I/O, concurrent writes, or loadEntries.
