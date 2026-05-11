# Feature: Telegram Provider

## Purpose
Implements the `MessageProvider` protocol for Telegram Bot API. Handles long polling, bot validation, message parsing, reply sending, and typing indicators.

## How It Works

```
start() → create Task for pollLoop()
pollLoop():
  → validateBot() via getMe API
  → if valid: set isConnected=true, notify via onStatusChange
  → loop: getUpdates(timeout=30) → processUpdate() for each
  → on error: set isConnected=false, sleep 5s, retry
stop() → cancel polling task, set isConnected=false
```

### Message Processing
- Parses Telegram Update objects using JSONSerialization (not Codable)
- Extracts: update_id, message.text, message.from.id, message.chat.id
- Ignores non-text messages (photos, stickers, etc.)
- Tracks lastUpdateID for offset-based polling

### Reply Sending
- POST to `/sendMessage` with `parse_mode: Markdown`
- No retry on failure, just logs error and throws

## API Surface (MessageProvider protocol)
- `start()` - begin long polling
- `stop()` - cancel polling
- `sendReply(_:to:)` - send text message to a conversation
- `sendTypingAction(to:)` - send "typing" chat action

### Additional Properties
- `isConnected: Bool`
- `botUsername: String?`
- `lastError: String?`
- `connectionAttempts: Int`
- `onStatusChange: ((Bool, String?) -> Void)?`

## Dependencies
- `Foundation` (URLSession for HTTP)
- `os` (Logger)

## Configuration
- `botToken` - Telegram Bot API token
- Long poll timeout: 30 seconds (hardcoded)
- HTTP request timeout: 35 seconds (hardcoded)
- Reconnect delay: 5 seconds (hardcoded)

## Known Limitations
- Only processes text messages (no photo, document, voice, callback queries)
- Uses JSONSerialization instead of Codable for Telegram API responses (inconsistent with the rest of the codebase)
- No retry logic for sendReply failures
- No message length validation before sending (Telegram has a 4096 char limit)
- `connectionAttempts` is incremented but never reset or used for backoff
- Bot token is included in URLs (standard for Telegram Bot API, but means it appears in logs if URL logging is enabled)
- No graceful handling of Telegram API rate limits (429 responses)

## Test Coverage
**None.**
