//
//  FeedbackServerApi.swift
//  BugseeFeedback
//
//  Copyright © 2026 Bugsee. All rights reserved.
//

import Foundation
import Bugsee

/// A single message as returned by the feedback thread API (`result.messages[]`, or the
/// `result` of a send). Mirrors Android's `ReceivedMessage`.
struct FeedbackReceivedMessage {
    let id: String
    let text: String
    /// `true` when the message was authored by the app user (server `type == "user"`),
    /// `false` for a developer/server reply.
    let isUser: Bool
    /// `true` when the server marks the message read.
    let isRead: Bool
    let receivedOnISO: String?
    let createdOnISO: String?
    let userEmail: String?
    let userName: String?

    init?(json: [String: Any]) {
        guard let id = json["_id"] as? String, let text = json["text"] as? String else {
            return nil
        }
        self.id = id
        self.text = text
        self.isUser = (json["type"] as? String) == "user"
        self.isRead = (json["status"] as? String) == "read"
        self.receivedOnISO = json["received_on"] as? String
        self.createdOnISO = json["created_on"] as? String
        let creator = json["created_by"] as? [String: Any]
        self.userEmail = creator?["email"] as? String
        self.userName = creator?["name"] as? String
    }

    /// Direct initializer (used by tests / stub servers).
    init(id: String, text: String, isUser: Bool, isRead: Bool = false,
         createdOnISO: String? = nil, receivedOnISO: String? = nil,
         userEmail: String? = nil, userName: String? = nil) {
        self.id = id
        self.text = text
        self.isUser = isUser
        self.isRead = isRead
        self.receivedOnISO = receivedOnISO
        self.createdOnISO = createdOnISO
        self.userEmail = userEmail
        self.userName = userName
    }
}

enum FeedbackServerError: Error {
    /// The SDK hasn't produced an app token yet (not launched / session not initialized).
    case notLaunched
    case transport(Error)
    case server(code: Int, message: String?)
    case malformedResponse
}

/// The feedback thread's server API as consumed by the chat engine. A protocol so the engine
/// (`ChatManager`) can be driven with a stub in tests.
protocol FeedbackApi {
    func pollMessages(since: String, till: String, limit: Int?) async throws -> [FeedbackReceivedMessage]
    func sendMessage(text: String, createdOnISO: String, userEmail: String?, userName: String?) async throws -> FeedbackReceivedMessage
    func markAsRead(ids: [String]) async throws
}

/// The request transport `FeedbackServerApi` builds on: it supplies the app token and executes
/// a `BugseeAPIRequest`, returning the unwrapped `result` dict (throwing `FeedbackServerError`
/// for transport/server-envelope failures). A protocol so `FeedbackServerApi`'s own request/
/// parsing logic can be tested against a stub without the live core communication layer.
protocol FeedbackTransport {
    var appToken: String? { get }
    func execute(_ request: BugseeAPIRequest) async throws -> [String: Any]
}

/// The production transport, built entirely on the core communication layer: the core supplies
/// the base endpoint, access-token auth, headers, TLS pinning and the `{result}`/`{error}`
/// envelope.
struct BugseeCommTransport: FeedbackTransport {

    private let comm = BugseeCommunicationManager.shared

    var appToken: String? { comm.appToken }

    func execute(_ request: BugseeAPIRequest) async throws -> [String: Any] {
        let response: BugseeAPIResponse = try await withCheckedThrowingContinuation { continuation in
            comm.execute(request) { response, error in
                if let error = error {
                    continuation.resume(throwing: FeedbackServerError.transport(error))
                } else if let response = response {
                    continuation.resume(returning: response)
                } else {
                    continuation.resume(throwing: FeedbackServerError.malformedResponse)
                }
            }
        }
        if let error = response.error {
            throw FeedbackServerError.server(code: error.code, message: error.message)
        }
        return response.result ?? [:]
    }
}

/// The feedback thread's server API. It names the feedback paths and shapes the request bodies /
/// parses the responses; all endpoint/auth/pinning/envelope concerns live behind the injected
/// `FeedbackTransport` (the core communication layer in production).
struct FeedbackServerApi: FeedbackApi {

    private let transport: FeedbackTransport

    init(transport: FeedbackTransport = BugseeCommTransport()) {
        self.transport = transport
    }

    private func messagesPath() throws -> String {
        guard let appToken = transport.appToken, !appToken.isEmpty else {
            throw FeedbackServerError.notLaunched
        }
        return "apps/\(appToken)/feedback/threads/current/messages"
    }

    /// Poll the thread for messages in the `[till, since]` window (Android's confusingly
    /// named bounds: `since` is the upper bound, `till` the lower). `limit` pages history.
    func pollMessages(since: String, till: String, limit: Int? = nil) async throws -> [FeedbackReceivedMessage] {
        var query = ["since": since, "till": till]
        if let limit = limit {
            query["limit"] = String(limit)
        }
        let request = BugseeAPIRequest.get(path: try messagesPath(), queryParams: query)
        let result = try await transport.execute(request)
        let rawMessages = result["messages"] as? [[String: Any]] ?? []
        return rawMessages.compactMap(FeedbackReceivedMessage.init(json:))
    }

    /// Send a user message. Returns the server-persisted message (with its id/timestamps).
    func sendMessage(text: String,
                     createdOnISO: String,
                     userEmail: String?,
                     userName: String?) async throws -> FeedbackReceivedMessage {
        var body: [String: Any] = ["message": ["text": text, "created_on": createdOnISO]]
        var user: [String: Any] = [:]
        if let userEmail = userEmail { user["email"] = userEmail }
        if let userName = userName { user["name"] = userName }
        if !user.isEmpty { body["user"] = user }

        let request = BugseeAPIRequest.post(path: try messagesPath(), jsonObject: body)
        let result = try await transport.execute(request)
        guard let message = FeedbackReceivedMessage(json: result) else {
            throw FeedbackServerError.malformedResponse
        }
        return message
    }

    /// Mark the given message ids as read.
    func markAsRead(ids: [String]) async throws {
        let path = try messagesPath() + "/statuses"
        let request = BugseeAPIRequest.post(path: path, jsonObject: ["ids": ids])
        _ = try await transport.execute(request)
    }
}
