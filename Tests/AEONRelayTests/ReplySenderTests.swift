import XCTest
@testable import AEONRelay

final class ReplySenderTests: XCTestCase {
    let sender = ReplySender()

    func testFormatReplySuccessful() {
        let result = ExecutionResult(
            id: "test-001",
            exitCode: 0,
            stdout: "Hello world\n",
            stderr: "",
            duration: 2.5,
            filesChanged: [],
            gitSummary: nil,
            truncated: false
        )
        let profile = WorkspaceProfile(
            name: "default", description: nil, workdir: "~/Projects",
            agent: nil, model: "gpt-4", backend: .copilot, timeout: 300, env: [:]
        )

        let reply = sender.formatReply(result, profile: profile, maxLength: 4096)
        XCTAssertTrue(reply.contains("Hello world"))
        XCTAssertTrue(reply.contains("✓"))
        XCTAssertTrue(reply.contains("gpt-4"))
        XCTAssertTrue(reply.contains("default"))
    }

    func testFormatReplyWithError() {
        let result = ExecutionResult(
            id: "test-002",
            exitCode: 1,
            stdout: "",
            stderr: "Error: file not found\n",
            duration: 0.5,
            filesChanged: [],
            gitSummary: nil,
            truncated: false
        )
        let profile = WorkspaceProfile(
            name: "dev", description: nil, workdir: "~/Projects",
            agent: "copilot", model: nil, backend: .copilot, timeout: 300, env: [:]
        )

        let reply = sender.formatReply(result, profile: profile, maxLength: 4096)
        XCTAssertTrue(reply.contains("✗"))
        XCTAssertTrue(reply.contains("file not found"))
    }

    func testFormatReplyTruncatesLongOutput() {
        let longOutput = String(repeating: "x", count: 5000)
        let result = ExecutionResult(
            id: "test-003",
            exitCode: 0,
            stdout: longOutput,
            stderr: "",
            duration: 1.0,
            filesChanged: [],
            gitSummary: nil,
            truncated: false
        )
        let profile = WorkspaceProfile(
            name: "default", description: nil, workdir: "~/Projects",
            agent: nil, model: nil, backend: .copilot, timeout: 300, env: [:]
        )

        let reply = sender.formatReply(result, profile: profile, maxLength: 4096)
        XCTAssertTrue(reply.contains("[truncated]"))
        XCTAssertLessThanOrEqual(reply.count, 4096 + 200) // some slack for footer
    }

    func testFormatReplyWithGitSummary() {
        let result = ExecutionResult(
            id: "test-004",
            exitCode: 0,
            stdout: "Done",
            stderr: "",
            duration: 10.0,
            filesChanged: ["file.swift"],
            gitSummary: " 1 file changed, 5 insertions(+), 2 deletions(-)",
            truncated: false
        )
        let profile = WorkspaceProfile(
            name: "dev", description: nil, workdir: "~/Projects",
            agent: nil, model: nil, backend: .claude, timeout: 300, env: [:]
        )

        let reply = sender.formatReply(result, profile: profile, maxLength: 4096)
        XCTAssertTrue(reply.contains("📝"))
        XCTAssertTrue(reply.contains("1 file changed"))
    }

    func testFormatReplyFallsBackToStderrWhenNoStdout() {
        let result = ExecutionResult(
            id: "test-005",
            exitCode: 0,
            stdout: "",
            stderr: "Warning: something happened",
            duration: 1.0,
            filesChanged: [],
            gitSummary: nil,
            truncated: false
        )
        let profile = WorkspaceProfile(
            name: "default", description: nil, workdir: "~/Projects",
            agent: nil, model: nil, backend: .copilot, timeout: 300, env: [:]
        )

        let reply = sender.formatReply(result, profile: profile, maxLength: 4096)
        XCTAssertTrue(reply.contains("Warning: something happened"))
    }
}
