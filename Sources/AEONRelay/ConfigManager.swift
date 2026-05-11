import Foundation
import AppKit
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

    // MARK: - Save

    func toggleChannel(_ name: String, enabled: Bool) {
        let dir = Self.relayHome.appendingPathComponent("channels")
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter({ $0.pathExtension == "json" }) else { return }

        for file in files {
            guard let data = try? Data(contentsOf: file),
                  var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["name"] as? String == name else { continue }

            json["enabled"] = enabled
            if let updated = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
                try? updated.write(to: file)
            }
            break
        }
        loadChannels()
    }

    func saveChannel(_ channel: ChannelConfig) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(channel) else { return }

        let dir = Self.relayHome.appendingPathComponent("channels")
        let filename = channel.name
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
        let path = dir.appendingPathComponent("\(filename).json")

        // If renaming, delete old file
        if let existing = findChannelFile(named: channel.name), existing != path {
            try? fm.removeItem(at: existing)
        }

        try? data.write(to: path)
        loadChannels()
        logActivity("Saved channel: \(channel.name)")
    }

    func deleteChannel(_ name: String) {
        if let file = findChannelFile(named: name) {
            try? fm.removeItem(at: file)
            loadChannels()
            logActivity("Deleted channel: \(name)")
        }
    }

    private func findChannelFile(named name: String) -> URL? {
        let dir = Self.relayHome.appendingPathComponent("channels")
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter({ $0.pathExtension == "json" }) else { return nil }
        for file in files {
            guard let data = try? Data(contentsOf: file),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["name"] as? String == name else { continue }
            return file
        }
        return nil
    }

    func saveBotToken(envName: String, token: String) {
        // Sanitize token: strip whitespace and surrounding quotes
        var cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if (cleanToken.hasPrefix("\"") && cleanToken.hasSuffix("\"")) ||
           (cleanToken.hasPrefix("'") && cleanToken.hasSuffix("'")) {
            cleanToken = String(cleanToken.dropFirst().dropLast())
        }
        guard !cleanToken.isEmpty else {
            logActivity("Skipped saving empty token for \(envName)")
            return
        }

        let credPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/aeon/credentials.env")

        // Ensure directory exists
        let credDir = credPath.deletingLastPathComponent()
        try? fm.createDirectory(at: credDir, withIntermediateDirectories: true)

        var lines: [String] = []
        if let contents = try? String(contentsOf: credPath, encoding: .utf8) {
            lines = contents.components(separatedBy: "\n")
        }

        // Replace or append
        var found = false
        for i in lines.indices {
            let parts = lines[i].split(separator: "=", maxSplits: 1)
            if parts.count >= 1 && parts[0].trimmingCharacters(in: .whitespaces) == envName {
                lines[i] = "\(envName)=\"\(cleanToken)\""
                found = true
                break
            }
        }
        if !found {
            if let last = lines.last, last.isEmpty {
                lines.insert("\(envName)=\"\(cleanToken)\"", at: lines.count - 1)
            } else {
                lines.append("\(envName)=\"\(cleanToken)\"")
            }
        }

        try? lines.joined(separator: "\n").write(to: credPath, atomically: true, encoding: .utf8)
        logActivity("Saved credential: \(envName)")
    }

    func openConfigFolder() {
        NSWorkspace.shared.open(Self.relayHome)
    }

    // MARK: - Audit

    func recentAuditEntries(limit: Int = 10) -> [AuditEntry] {
        let auditDir = Self.relayHome.appendingPathComponent("audit")
        guard let files = try? fm.contentsOfDirectory(at: auditDir, includingPropertiesForKeys: nil)
            .filter({ $0.pathExtension == "jsonl" })
            .sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var entries: [AuditEntry] = []

        for file in files.prefix(3) {
            guard let contents = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let lines = contents.split(separator: "\n")
            for line in lines.reversed() {
                guard let data = String(line).data(using: .utf8),
                      let entry = try? decoder.decode(AuditEntry.self, from: data) else { continue }
                entries.append(entry)
                if entries.count >= limit { return entries }
            }
        }
        return entries
    }

    // MARK: - Activity Log

    struct ActivityEntry: Identifiable {
        let id = UUID()
        let time: Date
        let message: String
        var timeString: String {
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss"
            return f.string(from: time)
        }
    }

    @Published var activityLog: [ActivityEntry] = []

    func logActivity(_ message: String) {
        let entry = ActivityEntry(time: Date(), message: message)
        DispatchQueue.main.async {
            self.activityLog.insert(entry, at: 0)
            if self.activityLog.count > 50 { self.activityLog.removeLast() }
        }
    }

    // MARK: - Update Check

    enum UpdateState {
        case idle, checking, upToDate, updateAvailable(String), updating, failed(String)
    }

    static let githubRepo = "ekeng92/aeon-relay"

    @Published var updateState: UpdateState = .idle

    func checkForUpdate() {
        updateState = .checking
        logActivity("Checking for updates...")

        let url = URL(string: "https://api.github.com/repos/\(Self.githubRepo)/commits/main")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        // Add PAT auth for private repos
        if let pat = loadGitHubPAT() {
            request.setValue("Bearer \(pat)", forHTTPHeaderField: "Authorization")
        }

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.updateState = .failed(error.localizedDescription)
                    self.logActivity("Update check failed: \(error.localizedDescription)")
                    return
                }
                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let sha = json["sha"] as? String else {
                    self.updateState = .failed("Invalid response")
                    self.logActivity("Update check: invalid response")
                    return
                }
                let remoteSHA = String(sha.prefix(7))
                let localSHA = BuildInfo.commitSHA
                if remoteSHA == localSHA || localSHA == "dev" {
                    self.updateState = .upToDate
                    self.logActivity("Up to date (\(remoteSHA))")
                } else {
                    self.updateState = .updateAvailable(remoteSHA)
                    self.logActivity("Update available: \(remoteSHA)")
                }
            }
        }.resume()
    }

    func runUpdate() {
        updateState = .updating
        logActivity("Installing update...")

        DispatchQueue.global(qos: .userInitiated).async {
            let repoDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Projects/aeon-relay")

            guard FileManager.default.fileExists(atPath: repoDir.path) else {
                DispatchQueue.main.async {
                    self.updateState = .failed("Repo not found at ~/Projects/aeon-relay")
                    self.logActivity("Update failed: repo not found")
                }
                return
            }

            let script = """
            cd "\(repoDir.path)" && git pull --ff-only && make install
            """
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-l", "-c", script]

            do {
                try process.run()
                process.waitUntilExit()
                DispatchQueue.main.async {
                    if process.terminationStatus == 0 {
                        self.logActivity("Update installed, app relaunching")
                    } else {
                        self.updateState = .failed("Install exited with code \(process.terminationStatus)")
                        self.logActivity("Update failed: exit code \(process.terminationStatus)")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.updateState = .failed(error.localizedDescription)
                    self.logActivity("Update failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - GitHub Auth

    private func loadGitHubPAT() -> String? {
        let credPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/aeon/credentials.env")
        guard let contents = try? String(contentsOf: credPath, encoding: .utf8) else { return nil }
        for line in contents.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1)
            if parts.count == 2 && parts[0].trimmingCharacters(in: .whitespaces) == "GITHUB_AEON_PRIME_PAT" {
                var value = String(parts[1]).trimmingCharacters(in: .whitespaces)
                if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
                   (value.hasPrefix("'") && value.hasSuffix("'")) {
                    value = String(value.dropFirst().dropLast())
                }
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }

    // MARK: - Dependency Checks

    private var _depCache: [String: Bool] = [:]

    var copilotAvailable: Bool {
        cachedCommandExists("copilot")
    }

    var claudeAvailable: Bool {
        cachedCommandExists("claude")
    }

    var codexAvailable: Bool {
        cachedCommandExists("codex")
    }

    func refreshDependencies() {
        _depCache.removeAll()
    }

    private func cachedCommandExists(_ name: String) -> Bool {
        if let cached = _depCache[name] { return cached }
        let result = commandExists(name)
        _depCache[name] = result
        return result
    }

    private func commandExists(_ name: String) -> Bool {
        // Check common paths first
        let paths = [
            "/usr/local/bin/\(name)",
            "\(NSHomeDirectory())/.local/bin/\(name)",
            "/opt/homebrew/bin/\(name)"
        ]
        if paths.contains(where: { fm.fileExists(atPath: $0) }) { return true }
        // Check NVM path for node-based CLIs
        if let nvmDir = ProcessInfo.processInfo.environment["NVM_DIR"] {
            let aliasPath = URL(fileURLWithPath: "\(nvmDir)/alias/default")
            let nodeVersion = (try? String(contentsOf: aliasPath, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !nodeVersion.isEmpty && fm.fileExists(atPath: "\(nvmDir)/versions/node/\(nodeVersion)/bin/\(name)") {
                return true
            }
        }
        // Fallback: shell out to `which`
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
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
    var name: String
    var provider: String
    var botToken: String
    var enabled: Bool
    var allowFrom: [String]
    var defaultProfile: String
    var profileRouting: [String: String]
    var greeting: String?
    var showTyping: Bool
    var maxMessageLength: Int

    static func newTelegram() -> ChannelConfig {
        ChannelConfig(
            name: "",
            provider: "telegram",
            botToken: "env:RELAY_TELEGRAM_TOKEN",
            enabled: false,
            allowFrom: [],
            defaultProfile: "default",
            profileRouting: [:],
            greeting: "AEON Relay connected.",
            showTyping: true,
            maxMessageLength: 4096
        )
    }
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
