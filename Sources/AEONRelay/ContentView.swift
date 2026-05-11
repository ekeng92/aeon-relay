import SwiftUI

struct ContentView: View {
    @ObservedObject var configManager: ConfigManager
    @ObservedObject var channelListener: ChannelListener
    @State private var expandedChannel: String?
    @State private var expandedProfile: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                statusCard
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                Divider().padding(.horizontal, 16)

                channelsSection
                    .padding(16)

                Divider().padding(.horizontal, 16)

                recentSection
                    .padding(16)

                Divider().padding(.horizontal, 16)

                profilesSection
                    .padding(16)

                Divider().padding(.horizontal, 16)

                quickActions
                    .padding(16)

                Divider().padding(.horizontal, 16)

                updateSection
                    .padding(16)

                Divider().padding(.horizontal, 16)

                activitySection
                    .padding(16)

                Divider()

                Button(action: { NSApp.terminate(nil) }) {
                    Text("Quit AEON Relay")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 10)
            }
        }
        .frame(width: 380, height: 640)
    }

    // MARK: - Status Card

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(statusColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle)
                        .font(.system(size: 16, weight: .semibold))
                    Text(statusSubtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(countsText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()
            }

            HStack(spacing: 16) {
                depIndicator("copilot", ok: configManager.copilotAvailable)
                depIndicator("claude", ok: configManager.claudeAvailable)
            }
            .font(.caption2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.quaternary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Channels

    private var channelsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CHANNELS")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            if configManager.channels.isEmpty {
                emptyState("No channels configured", detail: "Add JSON files to ~/.aeon-relay/channels/")
            } else {
                VStack(spacing: 6) {
                    ForEach(configManager.channels) { channel in
                        channelRow(channel)
                    }
                }
            }
        }
    }

    private func channelRow(_ channel: ChannelConfig) -> some View {
        let isConnected = channelListener.activeProviders[channel.name] ?? false
        let isExpanded = expandedChannel == channel.name

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(isConnected ? Color.green : (channel.enabled ? Color.orange : Color.gray))
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(channel.name)
                            .font(.caption.weight(.medium))
                        Text(channel.provider)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    Text(isConnected ? "connected" : (channel.enabled ? "connecting" : "disabled"))
                        .font(.system(size: 10))
                        .foregroundStyle(isConnected ? .green : .secondary)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { channel.enabled },
                    set: { channelListener.toggleChannel(channel.name, enabled: $0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()

                Button(action: { withAnimation(.easeInOut(duration: 0.2)) {
                    expandedChannel = isExpanded ? nil : channel.name
                }}) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.quaternary.opacity(0.5))
            }

            if isExpanded {
                channelDetail(channel)
                    .padding(.leading, 20)
                    .padding(.vertical, 6)
            }
        }
    }

    private func channelDetail(_ channel: ChannelConfig) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            detailRow("Default Profile", value: channel.defaultProfile)
            if !channel.profileRouting.isEmpty {
                detailRow("Routes", value: channel.profileRouting.map { "\($0.key) \u{2192} \($0.value)" }.joined(separator: ", "))
            }
            if !channel.allowFrom.isEmpty {
                detailRow("Allow", value: channel.allowFrom.joined(separator: ", "))
            }
            detailRow("Max Length", value: "\(channel.maxMessageLength)")
            HStack(spacing: 12) {
                Label(channel.showTyping ? "Typing on" : "Typing off", systemImage: channel.showTyping ? "keyboard" : "keyboard.badge.ellipsis")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Recent

    private var recentSection: some View {
        let entries = configManager.recentAuditEntries(limit: 5)

        return VStack(alignment: .leading, spacing: 8) {
            Text("RECENT EXECUTIONS")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            if entries.isEmpty {
                emptyState("No executions yet", detail: "Send a message to start")
            } else {
                VStack(spacing: 4) {
                    ForEach(entries, id: \.id) { entry in
                        recentRow(entry)
                    }
                }
            }
        }
    }

    private func recentRow(_ entry: AuditEntry) -> some View {
        let success = entry.exitCode == 0 && entry.error == nil
        let timeAgo = relativeTime(entry.timestamp)

        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(success ? .green : .red)
                .font(.caption)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.prompt)
                    .font(.caption)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(entry.profile)
                        .font(.caption2)
                        .foregroundStyle(.blue)
                    Text("\(String(format: "%.0f", entry.duration))s")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if !entry.filesChanged.isEmpty {
                        Text("\(entry.filesChanged.count) files")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(timeAgo)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Profiles

    private var profilesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("PROFILES (\(configManager.profiles.count))")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if configManager.profiles.isEmpty {
                emptyState("No profiles configured", detail: "Add JSON files to ~/.aeon-relay/profiles/")
            } else {
                VStack(spacing: 6) {
                    ForEach(configManager.profiles) { profile in
                        profileRow(profile)
                    }
                }
            }
        }
    }

    private func profileRow(_ profile: WorkspaceProfile) -> some View {
        let isExpanded = expandedProfile == profile.name
        let workdirExists = FileManager.default.fileExists(
            atPath: (profile.workdir as NSString).expandingTildeInPath
        )

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(profile.name)
                        .font(.caption.weight(.medium))
                    HStack(spacing: 6) {
                        Text(profile.backend.rawValue)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(.quaternary))
                        if let agent = profile.agent {
                            Text(agent)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                Spacer()
                Circle()
                    .fill(workdirExists ? Color.green : Color.red)
                    .frame(width: 6, height: 6)
                    .help(workdirExists ? "Workdir exists" : "Workdir not found")
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) {
                    expandedProfile = isExpanded ? nil : profile.name
                }}) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.quaternary.opacity(0.5))
            }

            if isExpanded {
                profileDetail(profile)
                    .padding(.leading, 12)
                    .padding(.vertical, 6)
            }
        }
    }

    private func profileDetail(_ profile: WorkspaceProfile) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let desc = profile.description {
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            detailRow("Workdir", value: profile.workdir.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
            if let model = profile.model {
                detailRow("Model", value: model)
            }
            detailRow("Timeout", value: "\(profile.timeout)s")
            if !profile.env.isEmpty {
                detailRow("Env", value: profile.env.keys.joined(separator: ", "))
            }
        }
    }

    // MARK: - Quick Actions

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ACTIONS")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                actionButton("Open Config", icon: "folder", tint: .blue) {
                    configManager.openConfigFolder()
                }
                actionButton("Open Audit", icon: "tray.full", tint: .blue) {
                    let auditDir = ConfigManager.relayHome.appendingPathComponent("audit")
                    NSWorkspace.shared.open(auditDir)
                }
            }

            HStack(spacing: 8) {
                let hasConnected = channelListener.activeProviders.values.contains(true)
                if hasConnected {
                    actionButton("Stop All", icon: "stop.fill", tint: .red) {
                        Task { await channelListener.stopAll() }
                        configManager.logActivity("Stopped all channels")
                    }
                } else {
                    actionButton("Start All", icon: "play.fill", tint: .green) {
                        channelListener.startAll()
                        configManager.logActivity("Starting all channels")
                    }
                }
                actionButton("Reload", icon: "arrow.clockwise", tint: Color(.systemGray)) {
                    channelListener.reloadConfig()
                    configManager.logActivity("Config reloaded")
                }
            }
        }
    }

    // MARK: - Update

    private var updateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("UPDATE")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Build: \(BuildInfo.commitSHA)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            switch configManager.updateState {
            case .idle:
                actionButton("Check for Updates", icon: "arrow.triangle.2.circlepath", tint: .blue) {
                    configManager.checkForUpdate()
                }
            case .checking:
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Checking...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 4)
            case .upToDate:
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Up to date")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(action: { configManager.checkForUpdate() }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            case .updateAvailable(let sha):
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(.orange)
                        Text("Update available (\(sha))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    actionButton("Install Update", icon: "arrow.down.to.line", tint: .orange) {
                        configManager.runUpdate()
                    }
                }
            case .updating:
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Installing update...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 4)
            case .failed(let msg):
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                        Text(msg)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    actionButton("Retry", icon: "arrow.triangle.2.circlepath", tint: .blue) {
                        configManager.checkForUpdate()
                    }
                }
            }
        }
    }

    // MARK: - Activity Log

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ACTIVITY")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            if configManager.activityLog.isEmpty {
                Text("No activity yet")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(configManager.activityLog.prefix(8)) { entry in
                        HStack(alignment: .top, spacing: 6) {
                            Text(entry.timeString)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.tertiary)
                            Text(entry.message)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Helpers

    private var statusColor: Color {
        let connected = channelListener.activeProviders.values.contains(true)
        let hasEnabled = configManager.channels.contains { $0.enabled }
        if connected { return .green }
        if hasEnabled { return .orange }
        return .red
    }

    private var statusTitle: String {
        let connected = channelListener.activeProviders.values.filter({ $0 }).count
        if connected > 0 { return "\(connected) Connected" }
        let hasEnabled = configManager.channels.contains { $0.enabled }
        if hasEnabled { return "Connecting" }
        return "No Channels"
    }

    private var statusSubtitle: String {
        let connected = channelListener.activeProviders.values.filter({ $0 }).count
        if connected > 0 {
            return "Listening for messages on \(connected) channel(s)"
        }
        let hasEnabled = configManager.channels.contains { $0.enabled }
        if hasEnabled { return "Establishing connections..." }
        return "Enable a channel to start receiving messages"
    }

    private var countsText: String {
        let channels = configManager.channels.count
        let enabled = configManager.channels.filter(\.enabled).count
        let profiles = configManager.profiles.count
        return "\(enabled)/\(channels) channels, \(profiles) profiles"
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
        }
    }

    private func emptyState(_ title: String, detail: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.body)
                .foregroundStyle(.secondary)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        if seconds < 86400 { return "\(seconds / 3600)h ago" }
        return "\(seconds / 86400)d ago"
    }

    private func depIndicator(_ name: String, ok: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ok ? .green : .red)
            Text(name)
        }
    }

    private func actionButton(_ title: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(tint)
        .controlSize(.small)
    }
}
