import Foundation
import os

private let logger = Logger(subsystem: "com.aeon.relay", category: "ChannelListener")

final class ChannelListener: ObservableObject {
    @Published var activeProviders: [String: Bool] = [:]  // id -> connected
    @Published var channelErrors: [String: String] = [:]  // id -> error message
    @Published var channelBots: [String: String] = [:]    // id -> @username

    private var providers: [String: TelegramProvider] = [:]
    private let configManager: ConfigManager
    private let executionEngine = ExecutionEngine()
    private let auditLogger = AuditLogger()
    private let replySender = ReplySender()
    private var securityManager = SecurityManager()

    // Track running executions per profile
    private var runningExecutions: Set<String> = []
    private var runningTasks: [String: Task<Void, Never>] = [String: Task<Void, Never>]()
    private var executionQueue: [(IncomingMessage, ChannelConfig, WorkspaceProfile)] = []
    private var channelProfileOverrides: [String: String] = [:]

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
                        self.channelErrors.removeValue(forKey: name)
                        self.channelBots.removeValue(forKey: name)
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
            DispatchQueue.main.async {
                self.channelErrors[channel.name] = "Unsupported provider: \(channel.provider)"
            }
            return
        }

        let botToken = resolveToken(channel.botToken)
        guard !botToken.isEmpty else {
            logger.error("No bot token for channel \(channel.name)")
            DispatchQueue.main.async {
                self.activeProviders[channel.name] = false
                self.channelErrors[channel.name] = "Bot token not found. Check credentials.env for the env var specified in channel config."
            }
            configManager.logActivity("\(channel.name): bot token not found")
            return
        }

        configManager.logActivity("Starting channel: \(channel.name)")
        DispatchQueue.main.async {
            self.channelErrors.removeValue(forKey: channel.name)
        }

        let provider = TelegramProvider(id: channel.name, botToken: botToken) { [weak self] message in
            guard let self = self else { return }
            Task {
                await self.handleMessage(message, channel: channel)
            }
        }

        provider.onStatusChange = { [weak self] connected, error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.activeProviders[channel.name] = connected
                if let error = error {
                    self.channelErrors[channel.name] = error
                    self.configManager.logActivity("\(channel.name): \(error)")
                } else if connected {
                    self.channelErrors.removeValue(forKey: channel.name)
                    if let username = provider.botUsername {
                        self.channelBots[channel.name] = "@\(username)"
                    }
                    self.configManager.logActivity("\(channel.name) connected\(provider.botUsername.map { " as @\($0)" } ?? "")")

                    // Send greeting to allowed chat IDs
                    if let greeting = channel.greeting, !greeting.isEmpty {
                        for chatID in channel.allowFrom {
                            Task {
                                let conv = ConversationID(provider: channel.name, chatID: chatID)
                                try? await provider.sendReply(greeting, to: conv)
                            }
                        }
                    }
                }
            }
        }

        providers[channel.name] = provider
        DispatchQueue.main.async {
            self.activeProviders[channel.name] = false
        }

        Task {
            try? await provider.start()
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

        case "/use":
            if parts.count > 1 {
                let profileName = String(parts[1]).trimmingCharacters(in: .whitespaces)
                if configManager.profileNamed(profileName) != nil {
                    channelProfileOverrides[channel.name] = profileName
                    await sendReply("Switched to profile: \(profileName)", to: message, channel: channel)
                } else {
                    let available = configManager.profiles.map(\.name).joined(separator: ", ")
                    await sendReply("Profile '\(profileName)' not found. Available: \(available)", to: message, channel: channel)
                }
            } else {
                let current = resolveProfile(message: message, channel: channel)
                let available = configManager.profiles.map(\.name).joined(separator: ", ")
                await sendReply("Current: \(current)\nAvailable: \(available)", to: message, channel: channel)
            }

        case "/cancel":
            if runningExecutions.isEmpty {
                await sendReply("No running executions to cancel.", to: message, channel: channel)
            } else {
                let cancelled = runningExecutions.count
                for (_, task) in runningTasks {
                    task.cancel()
                }
                runningTasks.removeAll()
                runningExecutions.removeAll()
                await sendReply("Cancelled \(cancelled) running execution(s).", to: message, channel: channel)
            }

        default:
            await sendReply("Unknown command. Use /help for available commands.", to: message, channel: channel)
        }
    }

    private func resolveProfile(message: IncomingMessage, channel: ChannelConfig) -> String {
        // Check per-channel override from /use command
        if let override = channelProfileOverrides[channel.name] {
            return override
        }
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
