import Foundation
import os

private let logger = Logger(subsystem: "com.aeon.relay", category: "Audit")

struct AuditEntry: Codable {
    let id: String
    let timestamp: Date
    let channel: String
    let profile: String
    let senderID: String
    let prompt: String
    let backend: String
    let agent: String?
    let model: String?
    let workdir: String
    let duration: TimeInterval
    let exitCode: Int32
    let filesChanged: [String]
    let gitDiff: String?
    let replyLength: Int
    let replyTruncated: Bool
    let error: String?
}

final class AuditLogger {
    private let auditDir: URL

    init() {
        auditDir = ConfigManager.relayHome.appendingPathComponent("audit")
        try? FileManager.default.createDirectory(at: auditDir, withIntermediateDirectories: true)
    }

    func log(_ entry: AuditEntry) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let filename = "\(formatter.string(from: entry.timestamp)).jsonl"
        let fileURL = auditDir.appendingPathComponent(filename)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entry) else {
            logger.error("Failed to encode audit entry \(entry.id)")
            return
        }

        var line = data
        line.append(contentsOf: "\n".utf8)

        if FileManager.default.fileExists(atPath: fileURL.path) {
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                handle.seekToEndOfFile()
                handle.write(line)
                handle.closeFile()
            }
        } else {
            try? line.write(to: fileURL)
        }

        logger.info("Audit entry written: \(entry.id)")
    }

    func loadEntries(date: Date? = nil) -> [AuditEntry] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let targetDate = date ?? Date()
        let filename = "\(formatter.string(from: targetDate)).jsonl"
        let fileURL = auditDir.appendingPathComponent(filename)

        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return contents.split(separator: "\n").compactMap { line in
            guard let data = String(line).data(using: .utf8) else { return nil }
            return try? decoder.decode(AuditEntry.self, from: data)
        }
    }
}
