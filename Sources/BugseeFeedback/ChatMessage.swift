//
//  ChatMessage.swift
//  BugseeFeedback
//
//  Copyright © 2026 Bugsee. All rights reserved.
//

import Foundation

/// A feedback message in the local model. Conforms to the public `BugseeFeedbackMessage`
/// surfaced to the host, and carries the local delivery state used for pending-send retry.
struct ChatMessage: Identifiable, Equatable, Codable, BugseeFeedbackMessage {
    /// Server id once delivered; a local UUID while a user message is pending.
    let id: String
    let message: String
    let type: BugseeFeedbackMessageType
    let timeSent: Date
    let timeReceived: Date?
    /// `false` while a user message is queued/in-flight and not yet acknowledged.
    var isDelivered: Bool
    var isRead: Bool

    var isUser: Bool { type == .user }
}

extension ChatMessage {
    /// Build a delivered message from a server payload.
    init(server: FeedbackReceivedMessage) {
        self.id = server.id
        self.message = server.text
        self.type = server.isUser ? .user : .server
        self.timeSent = ISO8601DateParsing.date(from: server.createdOnISO) ?? Date()
        self.timeReceived = ISO8601DateParsing.date(from: server.receivedOnISO)
        self.isDelivered = true
        self.isRead = server.isRead
    }
}

/// Shared ISO-8601 parsing/formatting for the feedback timestamps the server exchanges.
enum ISO8601DateParsing {
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let fallbackFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func date(from iso: String?) -> Date? {
        guard let iso = iso else { return nil }
        return formatter.date(from: iso) ?? fallbackFormatter.date(from: iso)
    }

    static func string(from date: Date) -> String {
        return formatter.string(from: date)
    }
}
