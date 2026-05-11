import Foundation
import os

private let logger = Logger(subsystem: "com.aeon.relay", category: "ChannelListener")

final class ChannelListener: ObservableObject {
    @Published var activeProviders: [String: Bool] = [:] // id -> connected

    private var providers: [String: TelegramProvider] = [:]
    private let configManager: ConfigManager
    private let executionEngine = ExecutionEngine()
    private let auditLogger = AuditLogger()
    private let replySender = ReplySender()
    private var securityManager = SecurityManager()

    // Track running executions per profile
    private var runningExecutions: Set<String> = []
    private var executionQueue: [(IncomingMessage, ChannelConfig, WorkspaceProfile)] = []

    init(configManager: ConfigManager) {
        self.configManager = configManager
    }

    func startAll() {
        for channel in configManager.channels where channel.enabled {
            startChannel(channel)
        }
    }

    func stopAll() async {
        for (_, provider) in providers {
            await provider.stop()
        }
        providers.removeAll()
        activeProviders.removeAll()
    }

    func toggleChannel(_ name: String, enabled: Bool) {
        configManager.toggleChannel(name, enabled: enabled)
        if enabled {
            if let channel = configManager.channels.first(where: { $0.name == name }) {
                startChannel(channel)
            }
        } else {
            if let provider = providers[name] {
                Task {
                    await provider.stop()
                    DispatchQueue.main.async {
                        self.providers.removeValue(forKey: name)
                        self.activeProviders.removeValue(forKey: name)
                    }
                }
            }
        }
    }

    func reloadConfig() {
        Task {
            await stopAll()
            DispatchQueue.main.async {
                self.configManager.loadConfig()
                self.startAll()
            }
        }
    }

    private func startChannel(_ channel: ChannelConfig) {
        guard channel.provider == "telegram" else {
            logger.warning("Unsupported provider: \(channel.provider)")
            return
        }

        let botToken = resolveToken(channel.botToken)
        guard !botToken.isEmpty else {
            logger.error("No bot token for channel \(channel.name)")
            return
        }

        configManager.logActivity("Starting channel: \(channel.name)")

        let provider = TelegramProvider(id: channel.name, botToken: botToken) { [weak self] message in
            guard let self = self else { return }
            Task {
                await self.handleMessage(message, channel: channel)
            }
        }

        providers[channel.name] = provider
        activeProviders[channel.name] = false

        Task {
            try? await provider.start()
            DispatchQueue.main.async {
                self.activeProviders[channel.name] = provider.isConnected
                if provider.isConnected {
                    self.configManager.logActivity("\(channel.name) connected")
                } else {
                    self.configManager.logActivity("\(channel.name) failed to connect")
                }
            }
        }
    }

    private func handleMessage(_ message: IncomingMessage, channel: ChannelConfig) async {
        // Security check
        let authResult = securityManager.authorize(message, channel: channel, rateLimit: configManager.globalConfig.rateLimitPerMinute)
        guard case .authorized = authResult else {
            logger.warning("Unauthorized message from \(message.senderID) on \(channel.name)")
            return // silent deny
        }

        // Rate limit check
        guard securityManager.checkRateLimit(senderID: message.senderID, limit: configManager.globalConfig.rateLimitPerMinute) else {
            logger.warning("Rate limited \(message.senderID)")
            return
        }

        // Check for slash commands
        if message.text.hasPrefix("/") {
            await handleSlashCommand(message, channel: channel)
            return
        }

        // Resolve profile
        let profileName = resolveProfile(message: message, channel: channel)
        guard let profile = configManager.profileNamed(profileName) else {
            logger.error("Profile not found: \(profileName)")
            await sendReply("Profile '\(profileName)' not found. Use /profiles to see available profiles.", to: message, channel: channel)
            return
        }

        // Send typing indicator
        if channel.showTyping, let provider = providers[channel.name] {
            await provider.sendTypingAction(to: message.conversationID.chatID)
        }

        // Execute
        do {
            let result = try await executionEngine.execute(prompt: message.text, profile: profile)

            // Format and send reply
            let reply = replySender.formatReply(result, profile: profile, maxLength: channel.maxMessageLength)
            await sendReply(reply, to: message, channel: channel)

            // Log audit
            let entry = AuditEntry(
                id: result.id,
                timestamp: Date(),
                channel: channel.name,
                profile: profile.name,
                senderID: message.senderID,
                prompt: message.text,
                backend: profile.backend.rawValue,
                agent: profile.agent,
                model: profile.model,
                workdir: (profile.workdir as NSString).expandingTildeInPath,
                duration: result.duration,
                exitCode: result.exitCode,
                filesChanged: result.filesChanged,
                gitDiff: result.gitSummary,
                replyLength: reply.count,
                replyTruncated: result.truncated,
                error: result.exitCode != 0 ? result.stderr : nil
            )
            auditLogger.log(entry)

        } catch {
            logger.error("Execution failed: \(error.localizedDescription)")
            await sendReply("Execution failed: \(error.localizedDescription)", to: message, channel: channel)
        }
    }

    private func handleSlashCommand(_ message: IncomingMessage, channel: ChannelConfig) async {
        let text = message.text.trimmingCharacters(in: .whitespaces)
        let parts = text.split(separator: " ", maxSplits: 1)
        let command = String(parts[0]).lowercased()

        switch command {
        case "/help":
            let help = """
            Available commands:
            /status - Active profile and queue depth
            /profiles - List available profiles
            /use <name> - Switch active profile
            /history - Last 5 executions
            /cancel - Cancel running execution
            /help - This message
            """
            await sendReply(help, to: message, channel: channel)

        case "/status":
            let profileName = resolveProfile(message: message, channel: channel)
            let profile = configManager.profileNamed(profileName)
            let status = """
            Active profile: \(profileName)
            Backend: \(profile?.backend.rawValue ?? "unknown")
            Agent: \(profile?.agent ?? "default")
            Model: \(profile?.model ?? "default")
            Workdir: \(profile?.workdir ?? "unknown")
            """
            await sendReply(status, to: message, channel: channel)

        case "/profiles":
            let list = configManager.profiles.map { p in
                "• \(p.name) (\(p.backend.rawValue))\n  \(p.workdir)"
            }.joined(separator: "\n")
            let reply = configManager.profiles.isEmpty ? "No profiles configured." : "Available profiles:\n\(list)"
            await sendReply(reply, to: message, channel: channel)

        case "/history":
            let entries = auditLogger.loadEntries()
            let recent = entries.suffix(5)
            if recent.isEmpty {
                await sendReply("No recent executions.", to: message, channel: channel)
            } else {
                let list = recent.map { e in
                    let icon = e.exitCode == 0 ? "✓" : "✗"
                    let dur = String(format: "%.0f", e.duration)
                    let promptPreview = String(e.prompt.prefix(40))
                    return "\(icon) \"\(promptPreview)\" \(dur)s · \(e.profile)"
                }.joined(separator: "\n")
                await sendReply(list, to: message, channel: channel)
            }

        default:
            await sendReply("Unknown command. Use /help for available commands.", to: message, channel: channel)
        }
    }

    private func resolveProfile(message: IncomingMessage, channel: ChannelConfig) -> String {
        // Check profile routing prefixes
        for (prefix, profile) in channel.profileRouting {
            if message.text.hasPrefix(prefix) {
                return profile
            }
        }
        return channel.defaultProfile
    }

    private func sendReply(_ text: String, to message: IncomingMessage, channel: ChannelConfig) async {
        guard let provider = providers[channel.name] else { return }
        do {
            try await provider.sendReply(text, to: message.conversationID)
        } catch {
            logger.error("Failed to send reply on \(channel.name): \(error.localizedDescription)")
        }
    }

    private func resolveToken(_ tokenSpec: String) -> String {
        if tokenSpec.hasPrefix("env:") {
            let envName = String(tokenSpec.dropFirst(4))
            // Check credentials file first
            let credPath = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/aeon/credentials.env")
            if let contents = try? String(contentsOf: credPath, encoding: .utf8) {
                for line in contents.split(separator: "\n") {
                    let parts = line.split(separator: "=", maxSplits: 1)
                    if parts.count == 2 && parts[0].trimmingCharacters(in: .whitespaces) == envName {
                        var value = String(parts[1]).trimmingCharacters(in: .whitespaces)
                        // Strip surrounding quotes
                        if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
                           (value.hasPrefix("'") && value.hasSuffix("'")) {
                            value = String(value.dropFirst().dropLast())
                        }
                        return value
                    }
                }
            }
            // Fall back to environment variable
            return ProcessInfo.processInfo.environment[envName] ?? ""
        }
        return tokenSpec
    }
}
