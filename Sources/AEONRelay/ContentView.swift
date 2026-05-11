import SwiftUI

struct ContentView: View {
    @ObservedObject var configManager: ConfigManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                headerSection
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

                footerSection
                    .padding(16)
            }
        }
        .frame(width: 380, height: 520)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .foregroundColor(.green)
                .font(.title2)
            Text("AEON Relay")
                .font(.headline)
            Spacer()
            Text(BuildInfo.commitSHA)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Channels

    private var channelsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Channels")
                .font(.subheadline.bold())
                .foregroundColor(.secondary)

            if configManager.channels.isEmpty {
                emptyState("No channels configured", detail: "Edit ~/.aeon-relay/channels/")
            } else {
                ForEach(configManager.channels) { channel in
                    channelRow(channel)
                }
            }
        }
    }

    private func channelRow(_ channel: ChannelConfig) -> some View {
        HStack {
            Circle()
                .fill(channel.enabled ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(channel.name)
                    .font(.body)
                Text(channel.provider)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if channel.enabled {
                Text("active")
                    .font(.caption2)
                    .foregroundColor(.green)
            } else {
                Text("disabled")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Recent

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent")
                .font(.subheadline.bold())
                .foregroundColor(.secondary)
            emptyState("No executions yet", detail: "Send a message to start")
        }
    }

    // MARK: - Profiles

    private var profilesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Profiles (\(configManager.profiles.count))")
                .font(.subheadline.bold())
                .foregroundColor(.secondary)

            if configManager.profiles.isEmpty {
                emptyState("No profiles configured", detail: "Edit ~/.aeon-relay/profiles/")
            } else {
                ForEach(configManager.profiles) { profile in
                    profileRow(profile)
                }
            }
        }
    }

    private func profileRow(_ profile: WorkspaceProfile) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(profile.name)
                .font(.body)
            HStack(spacing: 8) {
                if let agent = profile.agent {
                    Text(agent).font(.caption).foregroundColor(.secondary)
                }
                if let model = profile.model {
                    Text(model).font(.caption).foregroundColor(.secondary)
                }
                Text(profile.workdir.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            Text("Config: ~/.aeon-relay/")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    // MARK: - Empty State

    private func emptyState(_ title: String, detail: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.body)
                .foregroundColor(.secondary)
            Text(detail)
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}
