import Foundation
import os

private let logger = Logger(subsystem: "com.aeon.relay", category: "Security")

struct SecurityManager {

    enum AuthResult {
        case authorized
        case denied(String)
    }

    private var messageTimestamps: [String: [Date]] = [:]

    func authorize(_ message: IncomingMessage, channel: ChannelConfig, rateLimit: Int) -> AuthResult {
        // 1. Sender allowlist
        guard channel.allowFrom.contains(message.senderID) else {
            logger.warning("Denied sender \(message.senderID) on channel \(channel.name)")
            return .denied("Sender not in allowlist")
        }

        // 2. Channel enabled
        guard channel.enabled else {
            return .denied("Channel is disabled")
        }

        return .authorized
    }

    mutating func checkRateLimit(senderID: String, limit: Int) -> Bool {
        let now = Date()
        let cutoff = now.addingTimeInterval(-60)
        var timestamps = messageTimestamps[senderID] ?? []
        timestamps = timestamps.filter { $0 > cutoff }
        if timestamps.count >= limit {
            return false
        }
        timestamps.append(now)
        messageTimestamps[senderID] = timestamps
        return true
    }
}
