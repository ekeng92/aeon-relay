import Foundation
import os

private let logger = Logger(subsystem: "com.aeon.relay", category: "Telegram")

final class TelegramProvider: MessageProvider {
    let id: String
    let displayName = "Telegram"
    private(set) var isConnected = false
    private(set) var botUsername: String?
    private(set) var lastError: String?
    private(set) var connectionAttempts = 0

    private let botToken: String
    private let onMessage: (IncomingMessage) -> Void
    private var lastUpdateID: Int = 0
    private var pollingTask: Task<Void, Never>?
    private let session = URLSession.shared
    var onStatusChange: ((Bool, String?) -> Void)?

    init(id: String, botToken: String, onMessage: @escaping (IncomingMessage) -> Void) {
        self.id = id
        self.botToken = botToken
        self.onMessage = onMessage
    }

    private var baseURL: String { "https://api.telegram.org/bot\(botToken)" }

    func start() async throws {
        logger.info("Starting Telegram provider '\(self.id)'")
        pollingTask = Task { await pollLoop() }
    }

    func stop() async {
        logger.info("Stopping Telegram provider '\(self.id)'")
        pollingTask?.cancel()
        pollingTask = nil
        isConnected = false
        onStatusChange?(false, nil)
    }

    func sendReply(_ message: String, to conversation: ConversationID) async throws {
        let url = URL(string: "\(baseURL)/sendMessage")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "chat_id": conversation.chatID,
            "text": message,
            "parse_mode": "Markdown"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            logger.error("Failed to send reply to \(conversation.chatID)")
            throw RelayError.sendFailed
        }
    }

    func sendTypingAction(to chatID: String) async {
        guard let url = URL(string: "\(baseURL)/sendChatAction") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["chat_id": chatID, "action": "typing"]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await session.data(for: request)
    }

    // MARK: - Long Polling

    private func pollLoop() async {
        logger.info("Poll loop started")
        connectionAttempts += 1

        // Validate bot token with getMe before starting
        do {
            let username = try await validateBot()
            botUsername = username
            isConnected = true
            lastError = nil
            onStatusChange?(true, nil)
            logger.info("Bot validated: @\(username)")
        } catch {
            let msg: String
            if let urlError = error as? URLError {
                msg = "Network error: \(urlError.localizedDescription)"
            } else {
                msg = error.localizedDescription
            }
            logger.error("Bot validation failed for '\(self.id)': \(msg)")
            isConnected = false
            lastError = msg
            onStatusChange?(false, msg)
            return
        }

        while !Task.isCancelled {
            do {
                let updates = try await getUpdates()
                for update in updates {
                    processUpdate(update)
                }
                if !isConnected {
                    isConnected = true
                    lastError = nil
                    onStatusChange?(true, nil)
                }
            } catch {
                if Task.isCancelled { break }
                let msg = error.localizedDescription
                logger.error("Poll error: \(msg)")
                isConnected = false
                lastError = "Poll error: \(msg)"
                onStatusChange?(false, lastError)
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
        isConnected = false
        onStatusChange?(false, nil)
        logger.info("Poll loop ended")
    }

    private func validateBot() async throws -> String {
        guard let url = URL(string: "\(baseURL)/getMe") else { throw RelayError.invalidURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RelayError.sendFailed
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RelayError.sendFailed
        }

        if httpResponse.statusCode == 401 {
            throw NSError(domain: "Telegram", code: 401, userInfo: [
                NSLocalizedDescriptionKey: "Invalid bot token (401 Unauthorized)"
            ])
        }

        guard let ok = json["ok"] as? Bool, ok,
              let result = json["result"] as? [String: Any],
              let username = result["username"] as? String else {
            let description = (json["description"] as? String) ?? "Unknown error"
            throw NSError(domain: "Telegram", code: httpResponse.statusCode, userInfo: [
                NSLocalizedDescriptionKey: description
            ])
        }

        return username
    }

    private func getUpdates() async throws -> [[String: Any]] {
        var urlString = "\(baseURL)/getUpdates?timeout=30"
        if lastUpdateID > 0 {
            urlString += "&offset=\(lastUpdateID + 1)"
        }
        guard let url = URL(string: urlString) else { throw RelayError.invalidURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 35 // slightly more than Telegram's long poll timeout

        let (data, _) = try await session.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ok = json["ok"] as? Bool, ok,
              let result = json["result"] as? [[String: Any]] else {
            return []
        }
        return result
    }

    private func processUpdate(_ update: [String: Any]) {
        guard let updateID = update["update_id"] as? Int else { return }
        lastUpdateID = max(lastUpdateID, updateID)

        guard let message = update["message"] as? [String: Any],
              let text = message["text"] as? String,
              let from = message["from"] as? [String: Any],
              let senderID = from["id"] as? Int,
              let chat = message["chat"] as? [String: Any],
              let chatID = chat["id"] as? Int else { return }

        let incoming = IncomingMessage(
            provider: id,
            senderID: String(senderID),
            conversationID: ConversationID(provider: id, chatID: String(chatID)),
            text: text,
            timestamp: Date(),
            replyTo: nil
        )
        onMessage(incoming)
    }
}

enum RelayError: Error {
    case invalidURL
    case sendFailed
    case executionFailed(Int32)
    case timeout
    case unauthorized
    case rateLimited
    case profileNotFound(String)
}
