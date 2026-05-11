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
        // Telegram's message limit is 4096 characters; split if needed
        let maxLen = 4096
        if message.count <= maxLen {
            try await sendSingleMessage(message, to: conversation)
        } else {
            // Split on newlines near the boundary to avoid mid-word breaks
            var remaining = message
            while !remaining.isEmpty {
                let chunk: String
                if remaining.count <= maxLen {
                    chunk = remaining
                    remaining = ""
                } else {
                    let cutIndex = remaining.index(remaining.startIndex, offsetBy: maxLen)
                    let searchRange = remaining.startIndex..<cutIndex
                    if let lastNewline = remaining.range(of: "\n", options: .backwards, range: searchRange) {
                        chunk = String(remaining[remaining.startIndex..<lastNewline.lowerBound])
                        remaining = String(remaining[lastNewline.upperBound...])
                    } else {
                        chunk = String(remaining.prefix(maxLen))
                        remaining = String(remaining.dropFirst(maxLen))
                    }
                }
                try await sendSingleMessage(chunk, to: conversation)
            }
        }
    }

    private func sendSingleMessage(_ message: String, to conversation: ConversationID) async throws {
        let url = URL(string: "\(baseURL)/sendMessage")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        struct SendMessageBody: Encodable {
            let chat_id: String
            let text: String
            let parse_mode: String
        }
        let body = SendMessageBody(chat_id: conversation.chatID, text: message, parse_mode: "Markdown")
        request.httpBody = try JSONEncoder().encode(body)

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
        struct ChatActionBody: Encodable {
            let chat_id: String
            let action: String
        }
        request.httpBody = try? JSONEncoder().encode(ChatActionBody(chat_id: chatID, action: "typing"))
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
                    connectionAttempts = 0
                    onStatusChange?(true, nil)
                }
            } catch {
                if Task.isCancelled { break }
                connectionAttempts += 1
                let msg = error.localizedDescription
                logger.error("Poll error: \(msg)")
                isConnected = false
                lastError = "Poll error: \(msg)"
                onStatusChange?(false, lastError)
                // Exponential backoff: 5s, 10s, 20s, 40s, capped at 60s
                let backoff = min(5.0 * pow(2.0, Double(min(connectionAttempts - 1, 4))), 60.0)
                logger.info("Reconnecting in \(String(format: "%.0f", backoff))s (attempt \(self.connectionAttempts))")
                try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
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

        if httpResponse.statusCode == 401 {
            throw NSError(domain: "Telegram", code: 401, userInfo: [
                NSLocalizedDescriptionKey: "Invalid bot token (401 Unauthorized)"
            ])
        }

        let decoded = try JSONDecoder().decode(TelegramAPIResponse<TelegramUser>.self, from: data)

        guard decoded.ok, let user = decoded.result, let username = user.username else {
            let description = decoded.description ?? "Unknown error"
            throw NSError(domain: "Telegram", code: httpResponse.statusCode, userInfo: [
                NSLocalizedDescriptionKey: description
            ])
        }

        return username
    }

    private func getUpdates() async throws -> [TelegramUpdate] {
        var urlString = "\(baseURL)/getUpdates?timeout=30"
        if lastUpdateID > 0 {
            urlString += "&offset=\(lastUpdateID + 1)"
        }
        guard let url = URL(string: urlString) else { throw RelayError.invalidURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 35 // slightly more than Telegram's long poll timeout

        let (data, _) = try await session.data(for: request)
        let decoded = try JSONDecoder().decode(TelegramAPIResponse<[TelegramUpdate]>.self, from: data)
        guard decoded.ok else { return [] }
        return decoded.result ?? []
    }

    private func processUpdate(_ update: TelegramUpdate) {
        lastUpdateID = max(lastUpdateID, update.update_id)

        guard let message = update.message,
              let text = message.text,
              let from = message.from,
              let chat = message.chat else { return }

        let incoming = IncomingMessage(
            provider: id,
            senderID: String(from.id),
            conversationID: ConversationID(provider: id, chatID: String(chat.id)),
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

// MARK: - Telegram API Codable Models

struct TelegramAPIResponse<T: Decodable>: Decodable {
    let ok: Bool
    let result: T?
    let description: String?
}

struct TelegramUser: Decodable {
    let id: Int
    let is_bot: Bool?
    let username: String?
    let first_name: String?
}

struct TelegramChat: Decodable {
    let id: Int
    let type: String?
}

struct TelegramMessage: Decodable {
    let message_id: Int?
    let from: TelegramUser?
    let chat: TelegramChat?
    let text: String?
    let date: Int?
}

struct TelegramUpdate: Decodable {
    let update_id: Int
    let message: TelegramMessage?
}
