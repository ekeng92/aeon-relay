import XCTest
@testable import AEONRelay

final class ExecutionEngineTests: XCTestCase {
    let engine = ExecutionEngine()

    private func makeProfile(
        backend: ExecutionBackend,
        agent: String? = nil,
        model: String? = nil
    ) -> WorkspaceProfile {
        WorkspaceProfile(
            name: "test", description: nil, workdir: "~/Projects",
            agent: agent, model: model, backend: backend, timeout: 300, env: [:]
        )
    }

    // MARK: - Copilot Backend

    func testCopilotBasicArgs() {
        let profile = makeProfile(backend: .copilot)
        let args = engine.buildArguments(backend: .copilot, profile: profile, prompt: "hello world")
        XCTAssertEqual(args.first, "copilot")
        XCTAssertTrue(args.last?.contains("hello world") == true)
    }

    func testCopilotWithAgentAndModel() {
        let profile = makeProfile(backend: .copilot, agent: "aeon-dev", model: "gpt-4")
        let args = engine.buildArguments(backend: .copilot, profile: profile, prompt: "test")
        XCTAssertTrue(args.contains("-a"))
        XCTAssertTrue(args.contains("aeon-dev"))
        XCTAssertTrue(args.contains("-m"))
        XCTAssertTrue(args.contains("gpt-4"))
    }

    func testCopilotEscapesSingleQuotes() {
        let profile = makeProfile(backend: .copilot)
        let args = engine.buildArguments(backend: .copilot, profile: profile, prompt: "it's a test")
        let joined = args.joined(separator: " ")
        // Should have escaped single quotes
        XCTAssertTrue(joined.contains("'\\''"))
    }

    // MARK: - Claude Backend

    func testClaudeBasicArgs() {
        let profile = makeProfile(backend: .claude)
        let args = engine.buildArguments(backend: .claude, profile: profile, prompt: "analyze this")
        XCTAssertEqual(args[0], "claude")
        XCTAssertEqual(args[1], "--print")
    }

    func testClaudeWithModel() {
        let profile = makeProfile(backend: .claude, model: "sonnet")
        let args = engine.buildArguments(backend: .claude, profile: profile, prompt: "test")
        XCTAssertTrue(args.contains("--model"))
        XCTAssertTrue(args.contains("sonnet"))
    }

    // MARK: - Codex Backend

    func testCodexArgs() {
        let profile = makeProfile(backend: .codex)
        let args = engine.buildArguments(backend: .codex, profile: profile, prompt: "fix bug")
        XCTAssertEqual(args[0], "codex")
        XCTAssertEqual(args[1], "exec")
    }

    // MARK: - Custom Backend (Sanitization)

    func testCustomRejectsSemicolons() {
        let profile = makeProfile(backend: .custom)
        let args = engine.buildArguments(backend: .custom, profile: profile, prompt: "ls; rm -rf /")
        // Should reject the semicolon component and the rm
        XCTAssertFalse(args.contains(";"))
    }

    func testCustomRejectsPipes() {
        let profile = makeProfile(backend: .custom)
        let args = engine.buildArguments(backend: .custom, profile: profile, prompt: "cat file | grep secret")
        XCTAssertFalse(args.contains("|"))
    }

    func testCustomRejectsBackticks() {
        let profile = makeProfile(backend: .custom)
        let args = engine.buildArguments(backend: .custom, profile: profile, prompt: "`whoami`")
        // Should produce echo with invalid message
        XCTAssertTrue(args.contains("echo") || args.isEmpty || args.first == "echo")
    }

    func testCustomAllowsCleanCommand() {
        let profile = makeProfile(backend: .custom)
        let args = engine.buildArguments(backend: .custom, profile: profile, prompt: "ls -la")
        XCTAssertEqual(args, ["ls", "-la"])
    }

    // MARK: - Cancel API

    func testCancelAllReturnsZeroWhenEmpty() {
        let count = engine.cancelAll()
        XCTAssertEqual(count, 0)
    }
}
