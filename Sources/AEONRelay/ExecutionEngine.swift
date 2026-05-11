import Foundation
import os

private let logger = Logger(subsystem: "com.aeon.relay", category: "Execution")

struct ExecutionResult {
    let id: String
    let exitCode: Int32
    let stdout: String
    let stderr: String
    let duration: TimeInterval
    let filesChanged: [String]
    let gitSummary: String?
    let truncated: Bool
}

final class ExecutionEngine {

    func execute(prompt: String, profile: WorkspaceProfile) async throws -> ExecutionResult {
        let id = generateID()
        let startTime = Date()

        let workdir = (profile.workdir as NSString).expandingTildeInPath
        let args = buildCommand(backend: profile.backend, profile: profile, prompt: prompt)

        logger.info("[\(id)] Executing: \(args.joined(separator: " "))")
        logger.info("[\(id)] Working directory: \(workdir)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", args.joined(separator: " ")]
        process.currentDirectoryURL = URL(fileURLWithPath: workdir)

        // Set environment
        var env = ProcessInfo.processInfo.environment
        for (key, value) in profile.env {
            env[key] = value
        }
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        // Set timeout
        let timeoutSeconds = profile.timeout
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: UInt64(timeoutSeconds) * 1_000_000_000)
            if process.isRunning {
                logger.warning("[\(id)] Timeout after \(timeoutSeconds)s, killing process")
                process.terminate()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if process.isRunning { process.interrupt() }
            }
        }

        process.waitUntilExit()
        timeoutTask.cancel()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        let duration = Date().timeIntervalSince(startTime)

        // Get git diff summary
        let gitSummary = getGitSummary(workdir: workdir)
        let filesChanged = getChangedFiles(workdir: workdir)

        logger.info("[\(id)] Completed in \(String(format: "%.1f", duration))s, exit \(process.terminationStatus)")

        return ExecutionResult(
            id: id,
            exitCode: process.terminationStatus,
            stdout: stdout,
            stderr: stderr,
            duration: duration,
            filesChanged: filesChanged,
            gitSummary: gitSummary,
            truncated: false
        )
    }

    private func buildCommand(backend: ExecutionBackend, profile: WorkspaceProfile, prompt: String) -> [String] {
        let escapedPrompt = prompt.replacingOccurrences(of: "'", with: "'\\''")
        switch backend {
        case .copilot:
            var parts = ["copilot"]
            if let agent = profile.agent { parts += ["-a", agent] }
            if let model = profile.model { parts += ["-m", model] }
            parts.append("'\(escapedPrompt)'")
            return parts

        case .claude:
            var parts = ["claude", "--print"]
            if let model = profile.model { parts += ["--model", model] }
            parts.append("'\(escapedPrompt)'")
            return parts

        case .codex:
            return ["codex", "exec", "'\(escapedPrompt)'"]

        case .custom:
            return [escapedPrompt] // custom commands handle their own structure
        }
    }

    private func getGitSummary(workdir: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["diff", "--stat", "HEAD"]
        process.currentDirectoryURL = URL(fileURLWithPath: workdir)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return output?.isEmpty == true ? nil : output
        } catch {
            return nil
        }
    }

    private func getChangedFiles(workdir: String) -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["diff", "--name-only", "HEAD"]
        process.currentDirectoryURL = URL(fileURLWithPath: workdir)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        } catch {
            return []
        }
    }

    private func generateID() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let ts = formatter.string(from: Date())
        let suffix = String(format: "%04x", Int.random(in: 0..<0xFFFF))
        return "relay-\(ts)-\(suffix)"
    }
}
