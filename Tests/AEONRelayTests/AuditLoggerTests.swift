import XCTest
@testable import AEONRelay

final class AuditLoggerTests: XCTestCase {
    func testAuditEntryEncoding() throws {
        let entry = AuditEntry(
            id: "relay-test-001",
            timestamp: Date(),
            channel: "telegram-dev",
            profile: "default",
            senderID: "123",
            prompt: "test prompt",
            backend: "copilot",
            agent: "dev",
            model: "claude-sonnet-4",
            workdir: "/tmp/test",
            duration: 12.5,
            exitCode: 0,
            filesChanged: ["file.ts"],
            gitDiff: "1 file changed",
            replyLength: 100,
            replyTruncated: false,
            error: nil
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(entry)
        XCTAssertFalse(data.isEmpty)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(AuditEntry.self, from: data)
        XCTAssertEqual(decoded.id, "relay-test-001")
        XCTAssertEqual(decoded.channel, "telegram-dev")
        XCTAssertEqual(decoded.exitCode, 0)
        XCTAssertEqual(decoded.filesChanged, ["file.ts"])
    }
}
