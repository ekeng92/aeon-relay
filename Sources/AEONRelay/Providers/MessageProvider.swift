import Foundation

struct ConversationID: Hashable, Codable {
    let provider: String
    let chatID: String
}

struct IncomingMessage {
    let provider: String
    let senderID: String
    let conversationID: ConversationID
    let text: String
    let timestamp: Date
    let replyTo: String?
}

protocol MessageProvider {
    var id: String { get }
    var displayName: String { get }
    var isConnected: Bool { get }

    func start() async throws
    func stop() async
    func sendReply(_ message: String, to conversation: ConversationID) async throws
}
