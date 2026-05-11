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

    // MARK: - Dependency Checks

    var copilotAvailable: Bool {
        let paths = [
            "/usr/local/bin/copilot",
            "\(NSHomeDirectory())/.local/bin/copilot"
        ]
        if paths.contains(where: { fm.fileExists(atPath: $0) }) { return true }
        // Check NVM path
        if let nvmDir = ProcessInfo.processInfo.environment["NVM_DIR"] {
            let nodeVersion = (try? String(contentsOf: URL(fileURLWithPath: "\(nvmDir)/alias/default"), encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !nodeVersion.isEmpty && fm.fileExists(atPath: "\(nvmDir)/versions/node/\(nodeVersion)/bin/copilot") {
                return true
            }
        }
        return false
    }

    var claudeAvailable: Bool {
        fm.fileExists(atPath: "/usr/local/bin/claude") ||
        fm.fileExists(atPath: "\(NSHomeDirectory())/.local/bin/claude")
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
