import XCTest
@testable import AEONRelay

final class ConfigManagerTests: XCTestCase {
    func testGlobalConfigDefaults() throws {
        let config = GlobalConfig()
        XCTAssertEqual(config.version, 1)
        XCTAssertEqual(config.maxConcurrentExecutions, 3)
        XCTAssertEqual(config.defaultTimeout, 300)
        XCTAssertEqual(config.rateLimitPerMinute, 10)
    }

    func testChannelConfigDecoding() throws {
        let json = """
        {
            "name": "test-channel",
            "provider": "telegram",
            "botToken": "test-token",
            "enabled": true,
            "allowFrom": ["123"],
            "defaultProfile": "default",
            "profileRouting": {},
            "greeting": "Hello",
            "showTyping": true,
            "maxMessageLength": 4096
        }
        """.data(using: .utf8)!

        let channel = try JSONDecoder().decode(ChannelConfig.self, from: json)
        XCTAssertEqual(channel.name, "test-channel")
        XCTAssertEqual(channel.provider, "telegram")
        XCTAssertTrue(channel.enabled)
        XCTAssertEqual(channel.allowFrom, ["123"])
    }

    func testWorkspaceProfileDecoding() throws {
        let json = """
        {
            "name": "test-profile",
            "description": "Test",
            "workdir": "~/Projects/test",
            "agent": "dev",
            "model": "claude-sonnet-4",
            "backend": "copilot",
            "timeout": 300,
            "env": {}
        }
        """.data(using: .utf8)!

        let profile = try JSONDecoder().decode(WorkspaceProfile.self, from: json)
        XCTAssertEqual(profile.name, "test-profile")
        XCTAssertEqual(profile.backend, .copilot)
        XCTAssertEqual(profile.agent, "dev")
    }

    func testExecutionBackendValues() {
        XCTAssertEqual(ExecutionBackend.copilot.rawValue, "copilot")
        XCTAssertEqual(ExecutionBackend.claude.rawValue, "claude")
        XCTAssertEqual(ExecutionBackend.codex.rawValue, "codex")
        XCTAssertEqual(ExecutionBackend.custom.rawValue, "custom")
    }
}
