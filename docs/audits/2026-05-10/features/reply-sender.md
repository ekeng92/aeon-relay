# Feature: Reply Sender

## Purpose
Formats execution results into human-readable messages for channel reply, with truncation and status footer.

## How It Works

```
formatReply(result, profile, maxLength) →
  → take stdout, fall back to stderr if stdout empty
  → truncate to maxLength - 200 chars (leave room for footer)
  → build footer: ✓/✗ icon, duration, model, profile name
  → append git summary last line if present
  → if error: append last 10 lines of stderr in code block
  → return combined string
```

## API Surface
- `formatReply(_:profile:maxLength:) -> String`

## Dependencies
- `Foundation` only

## Known Limitations
- Truncation is character-based, not byte-based (Unicode characters could push the actual byte count over Telegram's limit)
- Markdown formatting in the output could conflict with Telegram's Markdown parser (unmatched backticks, asterisks in file paths)
- No escaping of Telegram Markdown special characters in user output
- Error block uses triple backticks which could be broken if stderr contains triple backticks
- Footer format is hardcoded, not configurable
- Git summary extracts only the last line, which is the summary line (intentional, but loses file-level detail)

## Test Coverage
**None.**
