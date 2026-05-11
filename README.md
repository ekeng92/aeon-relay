# AEON Relay

Remote AI agent execution from any messaging channel.

Send a message from Telegram, get Copilot CLI work done in your workspace, receive the result back in the chat.

## Features

- **Telegram integration** with long polling (no webhook, works behind NAT)
- **Copilot CLI execution** with full workspace context, agent modes, and model selection
- **Workspace profiles** for channel-per-project routing
- **Sender allowlist** security with rate limiting
- **JSONL audit logs** for every execution
- **Native macOS menu bar app** with connection status, recent runs, and settings

## Requirements

- macOS 13 (Ventura) or later
- Xcode CommandLineTools (`xcode-select --install`)
- GitHub Copilot CLI (`npm install -g @anthropic-ai/copilot`)

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/ekeng92/aeon-relay/main/scripts/remote-install.sh | bash
```

Or clone and build locally:

```bash
git clone https://github.com/ekeng92/aeon-relay.git
cd aeon-relay
make install
```

## Quick Start

1. Create a Telegram bot via [@BotFather](https://t.me/BotFather) and get the bot token
2. Get your Telegram chat ID (message the bot, check `getUpdates`)
3. Edit `~/.aeon-relay/channels/telegram.json` with your bot token and chat ID
4. Edit `~/.aeon-relay/profiles/default.json` with your workspace path
5. The app starts listening automatically

## Configuration

All config lives in `~/.aeon-relay/`:

```
~/.aeon-relay/
├── config.json              # Global settings
├── channels/
│   └── telegram.json        # Channel config (bot token, allowlist, routing)
├── profiles/
│   └── default.json         # Workspace profile (workdir, agent, model)
├── audit/
│   └── YYYY-MM-DD.jsonl     # Execution audit logs
└── logs/                    # Runtime logs
```

## In-Channel Commands

| Command | Action |
|---------|--------|
| `/status` | Show active profile and queue depth |
| `/profiles` | List available profiles |
| `/use <name>` | Switch active profile |
| `/history` | Last 5 executions |
| `/cancel` | Cancel running execution |
| `/help` | List commands |

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/ekeng92/aeon-relay/main/scripts/remote-install.sh | bash -s -- --uninstall
```

## License

MIT
