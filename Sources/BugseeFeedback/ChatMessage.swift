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

/// A shared, immutable `ISO8601DateFormatter`. The type is not `Sendable`, but Foundation
/// documents formatting and parsing as thread-safe on a formatter that is configured once
/// and never mutated afterwards -- which is exactly how the two below are used. The box
/// states that to the compiler without `nonisolated(unsafe)`, which would raise the
/// package's floor to a Swift 5.10 toolchain.
private struct SharedISO8601Formatter: @unchecked Sendable {
    let formatter: ISO8601DateFormatter

    init(options: ISO8601DateFormatter.Options) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = options
        self.formatter = formatter
    }
}

/// Shared ISO-8601 parsing/formatting for the feedback timestamps the server exchanges.
enum ISO8601DateParsing {
    private static let primary = SharedISO8601Formatter(
        options: [.withInternetDateTime, .withFractionalSeconds])

    /// The server omits fractional seconds on some timestamps, which the primary formatter
    /// rejects outright rather than tolerating.
    private static let fallback = SharedISO8601Formatter(options: [.withInternetDateTime])

    static func date(from iso: String?) -> Date? {
        guard let iso = iso else { return nil }
        return primary.formatter.date(from: iso) ?? fallback.formatter.date(from: iso)
    }

    static func string(from date: Date) -> String {
        return primary.formatter.string(from: date)
    }
}
