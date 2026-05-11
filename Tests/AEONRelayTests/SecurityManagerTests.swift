import XCTest
@testable import AEONRelay

final class SecurityManagerTests: XCTestCase {
    func testAuthorizedSender() {
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

        let result = manager.authorize(message, channel: channel, rateLimit: 10)
        if case .authorized = result {
            // pass
        } else {
            XCTFail("Expected authorized")
        }
    }

    func testDeniedSender() {
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

        let result = manager.authorize(message, channel: channel, rateLimit: 10)
        if case .denied = result {
            // pass
        } else {
            XCTFail("Expected denied")
        }
    }

    func testDisabledChannel() {
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

        let result = manager.authorize(message, channel: channel, rateLimit: 10)
        if case .denied = result {
            // pass
        } else {
            XCTFail("Expected denied for disabled channel")
        }
    }

    func testRateLimiting() {
        var manager = SecurityManager()
        // First 10 should pass
        for _ in 0..<10 {
            XCTAssertTrue(manager.checkRateLimit(senderID: "123", limit: 10))
        }
        // 11th should fail
        XCTAssertFalse(manager.checkRateLimit(senderID: "123", limit: 10))
    }
}
