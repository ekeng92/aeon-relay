import Foundation
import os

private let logger = Logger(subsystem: "com.aeon.relay", category: "Reply")

struct ReplySender {

    func formatReply(_ result: ExecutionResult, profile: WorkspaceProfile, maxLength: Int) -> String {
        var output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        // If there's stderr and no stdout, use stderr
        if output.isEmpty && !result.stderr.isEmpty {
            output = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Truncate if needed
        if output.count > maxLength - 200 { // leave room for footer
            output = String(output.prefix(maxLength - 200))
            output += "\n... [truncated]"
        }

        // Footer
        let durationStr = String(format: "%.0f", result.duration)
        let statusIcon = result.exitCode == 0 ? "✓" : "✗"
        var footer = "\(statusIcon) \(durationStr)s"
        if let model = profile.model { footer += " · \(model)" }
        footer += " · \(profile.name)"

        if let gitSummary = result.gitSummary, !gitSummary.isEmpty {
            let lastLine = gitSummary.split(separator: "\n").last.map(String.init) ?? gitSummary
            footer += "\n📝 \(lastLine)"
        }

        if result.exitCode != 0 {
            // Show last 10 lines of stderr for errors
            let stderrLines = result.stderr.split(separator: "\n")
            let errorLines = stderrLines.suffix(10).joined(separator: "\n")
            if !errorLines.isEmpty {
                output += "\n\nError:\n```\n\(errorLines)\n```"
            }
        }

        return "\(output)\n\n\(footer)"
    }
}
