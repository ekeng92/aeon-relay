# Feature: Security Manager

## Purpose
Validates incoming messages against sender allowlists and rate limits. Silent deny for unauthorized senders.

## How It Works

```
authorize(message, channel, rateLimit) →
  1. Check sender ID is in channel.allowFrom → deny if not
  2. Check channel is enabled → deny if not
  → return .authorized or .denied(reason)

checkRateLimit(senderID, limit) →
  → filter timestamps to last 60 seconds
  → if count >= limit → return false
  → append current timestamp → return true
```

## API Surface
- `authorize(_:channel:rateLimit:) -> AuthResult`
- `checkRateLimit(senderID:limit:) -> Bool` (mutating)

### AuthResult
- `.authorized`
- `.denied(String)` - with reason

## Dependencies
- `Foundation` (Date)
- `os` (Logger)

## Configuration
- Allowlist per channel (`channel.allowFrom`)
- Rate limit from global config (`rateLimitPerMinute`)

## Known Limitations
- Rate limit check is separate from authorize, meaning a denied sender still gets rate-limited (minor, but logically they should be skipped)
- `SecurityManager` is a struct with mutating methods, but ChannelListener calls it from async contexts without synchronization (potential data race on `messageTimestamps`)
- No IP-based restrictions (Telegram doesn't provide IP, so this is inherent)
- Allowlist comparison is exact string match only (no regex, no wildcards)
- Rate limit window is fixed at 60 seconds (not configurable)
- Rate limiting is in-memory only, resets on app restart

## Test Coverage
4 tests: authorized sender, denied sender, disabled channel, rate limiting. Core functionality is covered. Missing: rate limit window expiry, concurrent access.
