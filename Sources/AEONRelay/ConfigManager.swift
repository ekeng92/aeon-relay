import Foundation
import os

private let logger = Logger(subsystem: "com.aeon.relay", category: "Config")

final class ConfigManager: ObservableObject {
    static let relayHome = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".aeon-relay")

    @Published var globalConfig = GlobalConfig()
    @Published var channels: [ChannelConfig] = []
    @Published var profiles: [WorkspaceProfile] = []

    private let fm = FileManager.default

    // MARK: - Directory Structure

    func ensureDirectories() {
        let dirs = [
            Self.relayHome,
            Self.relayHome.appendingPathComponent("channels"),
            Self.relayHome.appendingPathComponent("profiles"),
            Self.relayHome.appendingPathComponent("audit"),
            Self.relayHome.appendingPathComponent("logs"),
        ]
        for dir in dirs {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        // Seed example configs on first run
        let configPath = Self.relayHome.appendingPathComponent("config.json")
        if !fm.fileExists(atPath: configPath.path) {
            seedExampleConfigs()
        }
    }

    // MARK: - Load

    func loadConfig() {
        loadGlobalConfig()
        loadChannels()
        loadProfiles()
        logger.info("Loaded \(self.channels.count) channels, \(self.profiles.count) profiles")
    }

    private func loadGlobalConfig() {
        let path = Self.relayHome.appendingPathComponent("config.json")
        guard let data = try? Data(contentsOf: path) else { return }
        let decoder = JSONDecoder()
        if let config = try? decoder.decode(GlobalConfig.self, from: data) {
            globalConfig = config
        }
    }

    private func loadChannels() {
        let dir = Self.relayHome.appendingPathComponent("channels")
        channels = loadJSONFiles(from: dir)
    }

    private func loadProfiles() {
        let dir = Self.relayHome.appendingPathComponent("profiles")
        profiles = loadJSONFiles(from: dir)
    }

    private func loadJSONFiles<T: Decodable>(from dir: URL) -> [T] {
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter({ $0.pathExtension == "json" }) else { return [] }
        let decoder = JSONDecoder()
        return files.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(T.self, from: data)
        }
    }

    // MARK: - Seed

    private func seedExampleConfigs() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let config = GlobalConfig()
        if let data = try? encoder.encode(config) {
            try? data.write(to: Self.relayHome.appendingPathComponent("config.json"))
        }

        let exampleChannel = ChannelConfig(
            name: "telegram-dev",
            provider: "telegram",
            botToken: "env:RELAY_TELEGRAM_TOKEN",
            enabled: false,
            allowFrom: ["YOUR_CHAT_ID"],
            defaultProfile: "default",
            profileRouting: [:],
            greeting: "AEON Relay connected. Send a message to execute via Copilot CLI.",
            showTyping: true,
            maxMessageLength: 4096
        )
        if let data = try? encoder.encode(exampleChannel) {
            try? data.write(to: Self.relayHome.appendingPathComponent("channels/telegram-dev.json"))
        }

        let exampleProfile = WorkspaceProfile(
            name: "default",
            description: "Default workspace profile",
            workdir: "~/Projects",
            agent: nil,
            model: nil,
            backend: .copilot,
            timeout: 300,
            env: [:]
        )
        if let data = try? encoder.encode(exampleProfile) {
            try? data.write(to: Self.relayHome.appendingPathComponent("profiles/default.json"))
        }

        logger.info("Seeded example configuration")
    }

    func profileNamed(_ name: String) -> WorkspaceProfile? {
        profiles.first { $0.name == name }
    }
}

// MARK: - Models

struct GlobalConfig: Codable {
    var version: Int = 1
    var maxConcurrentExecutions: Int = 3
    var defaultTimeout: Int = 300
    var rateLimitPerMinute: Int = 10
    var progressUpdateInterval: Int = 30
    var firstProgressDelay: Int = 15
    var logLevel: String = "info"
    var auditRetentionDays: Int = 90
    var voiceOnCompletion: Bool = true
    var notificationsEnabled: Bool = true
}

struct ChannelConfig: Codable, Identifiable {
    var id: String { name }
    let name: String
    let provider: String
    let botToken: String
    var enabled: Bool
    let allowFrom: [String]
    let defaultProfile: String
    let profileRouting: [String: String]
    let greeting: String?
    let showTyping: Bool
    let maxMessageLength: Int
}

struct WorkspaceProfile: Codable, Identifiable {
    var id: String { name }
    let name: String
    let description: String?
    let workdir: String
    let agent: String?
    let model: String?
    let backend: ExecutionBackend
    let timeout: Int
    let env: [String: String]
}

enum ExecutionBackend: String, Codable {
    case copilot
    case claude
    case codex
    case custom
}
