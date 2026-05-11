import XCTest
@testable import AEONRelay

final class SecurityManagerTests: XCTestCase {
    func testAuthorizedSender() async {
        let manager = SecurityManager()
        let channel = ChannelConfig(
            name: "test", provider: "telegram", botToken: "tok",
            enabled: true, allowFrom: ["123"], defaultProfile: "default",
            profileRouting: [:], greeting: nil, showTyping: false, maxMessageLength: 4096
        )
        let message = IncomingMessage(
            provider: "test", senderID: "123",
            conversationID: ConversationID(provider: "test", chatID: "123"),
            text: "hello", timestamp: Date(), replyTo: nil
        )

        let result = await manager.authorize(message, channel: channel, rateLimit: 10)
        if case .authorized = result {
            // pass
        } else {
            XCTFail("Expected authorized")
        }
    }

    func testDeniedSender() async {
        let manager = SecurityManager()
        let channel = ChannelConfig(
            name: "test", provider: "telegram", botToken: "tok",
            enabled: true, allowFrom: ["456"], defaultProfile: "default",
            profileRouting: [:], greeting: nil, showTyping: false, maxMessageLength: 4096
        )
        let message = IncomingMessage(
            provider: "test", senderID: "123",
            conversationID: ConversationID(provider: "test", chatID: "123"),
            text: "hello", timestamp: Date(), replyTo: nil
        )

        let result = await manager.authorize(message, channel: channel, rateLimit: 10)
        if case .denied = result {
            // pass
        } else {
            XCTFail("Expected denied")
        }
    }

    func testDisabledChannel() async {
        let manager = SecurityManager()
        let channel = ChannelConfig(
            name: "test", provider: "telegram", botToken: "tok",
            enabled: false, allowFrom: ["123"], defaultProfile: "default",
            profileRouting: [:], greeting: nil, showTyping: false, maxMessageLength: 4096
        )
        let message = IncomingMessage(
            provider: "test", senderID: "123",
            conversationID: ConversationID(provider: "test", chatID: "123"),
            text: "hello", timestamp: Date(), replyTo: nil
        )

        let result = await manager.authorize(message, channel: channel, rateLimit: 10)
        if case .denied = result {
            // pass
        } else {
            XCTFail("Expected denied for disabled channel")
        }
    }

    func testRateLimiting() async {
        let manager = SecurityManager()
        // First 10 should pass
        for _ in 0..<10 {
            let result = await manager.checkRateLimit(senderID: "123", limit: 10)
            XCTAssertTrue(result)
        }
        // 11th should fail
        let result = await manager.checkRateLimit(senderID: "123", limit: 10)
        XCTAssertFalse(result)
    }
}
