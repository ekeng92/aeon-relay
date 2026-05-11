import Foundation
import os

private let logger = Logger(subsystem: "com.aeon.relay", category: "Telegram")

final class TelegramProvider: MessageProvider {
    let id: String
    let displayName = "Telegram"
    private(set) var isConnected = false

    private let botToken: String
    private let onMessage: (IncomingMessage) -> Void
    private var lastUpdateID: Int = 0
    private var pollingTask: Task<Void, Never>?
    private let session = URLSession.shared

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
        isConnected = true

        while !Task.isCancelled {
            do {
                let updates = try await getUpdates()
                for update in updates {
                    processUpdate(update)
                }
            } catch {
                if Task.isCancelled { break }
                logger.error("Poll error: \(error.localizedDescription)")
                isConnected = false
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5s backoff
                isConnected = true
            }
        }
        isConnected = false
        logger.info("Poll loop ended")
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
