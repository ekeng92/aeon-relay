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

    // Allowed CLI tools for execution (prevents arbitrary command injection)
    private static let allowedBackends: Set<String> = ["copilot", "claude", "codex"]

    func execute(prompt: String, profile: WorkspaceProfile) async throws -> ExecutionResult {
        let id = generateID()
        let startTime = Date()

        let workdir = (profile.workdir as NSString).expandingTildeInPath
        let args = buildArguments(backend: profile.backend, profile: profile, prompt: prompt)

        logger.info("[\(id)] Executing: \(args.first ?? "unknown") with \(args.count - 1) args")
        logger.info("[\(id)] Working directory: \(workdir)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // Use -l -c with a single joined command to get login shell PATH resolution
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

        // Read pipes concurrently to prevent deadlock when output exceeds buffer size
        let stdoutTask = Task.detached { () -> Data in
            stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        }
        let stderrTask = Task.detached { () -> Data in
            stderrPipe.fileHandleForReading.readDataToEndOfFile()
        }

        // Set timeout with process group kill
        let timeoutSeconds = profile.timeout
        let processPID = process.processIdentifier
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: UInt64(timeoutSeconds) * 1_000_000_000)
            if process.isRunning {
                logger.warning("[\(id)] Timeout after \(timeoutSeconds)s, killing process group")
                // Kill the entire process group to clean up child processes
                kill(-processPID, SIGTERM)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if process.isRunning {
                    kill(-processPID, SIGKILL)
                }
            }
        }

        process.waitUntilExit()
        timeoutTask.cancel()

        let stdoutData = await stdoutTask.value
        let stderrData = await stderrTask.value

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

    private func buildArguments(backend: ExecutionBackend, profile: WorkspaceProfile, prompt: String) -> [String] {
        // Shell-safe escaping: wrap in single quotes, escape internal single quotes
        let escaped = "'" + prompt.replacingOccurrences(of: "'", with: "'\\''") + "'"

        switch backend {
        case .copilot:
            var parts = ["copilot"]
            if let agent = profile.agent { parts += ["-a", agent] }
            if let model = profile.model { parts += ["-m", model] }
            parts.append(escaped)
            return parts

        case .claude:
            var parts = ["claude", "--print"]
            if let model = profile.model { parts += ["--model", model] }
            parts.append(escaped)
            return parts

        case .codex:
            return ["codex", "exec", escaped]

        case .custom:
            // Custom backend: the prompt is treated as the executable name only.
            // No shell metacharacters are allowed to prevent command injection.
            let sanitized = prompt.components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }
                .map { component in
                    // Reject any shell metacharacters
                    let forbidden = CharacterSet(charactersIn: ";|&$`(){}[]!#~<>\\\"'")
                    if component.unicodeScalars.contains(where: { forbidden.contains($0) }) {
                        return ""
                    }
                    return component
                }
                .filter { !$0.isEmpty }
            guard !sanitized.isEmpty else {
                return ["echo", "'Invalid command: contains forbidden characters'"]
            }
            return sanitized
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
