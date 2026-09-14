//
//  ChatManager.swift
//  BugseeFeedback
//
//  Copyright © 2026 Bugsee. All rights reserved.
//

import Foundation

/// The feedback chat engine and single source of truth: the message list, the poll loop
/// (running only while the chat UI is visible — Android parity, no background polling), and
/// optimistic send with pending-delivery retry. An `actor`, so all message-list mutation is
/// serialized without explicit locks. Mirrors Android's `ChatManager`.
actor ChatManager {

    static let shared = ChatManager()

    private let api: FeedbackApi
    private let store: FeedbackStoring
    private var messages: [ChatMessage]
    private var pollTask: Task<Void, Never>?

    /// Dependencies default to the production server API + on-disk store; tests inject stubs.
    init(api: FeedbackApi = FeedbackServerApi(), store: FeedbackStoring = FeedbackStore()) {
        self.api = api
        self.store = store
        // Rehydrate the thread (including still-undelivered user messages) from disk.
        messages = store.load()
    }

    /// Poll cadence while the chat is open (Android's `POLL_INTERVAL_MS = 10_000`).
    private static let pollIntervalNanos: UInt64 = 10 * 1_000_000_000

    /// Invoked whenever the message list changes, so the UI can re-render.
    private var onChange: (@Sendable ([ChatMessage]) -> Void)?

    /// Invoked with the texts of newly-arrived inbound (developer/server) messages, so the
    /// host's BugseeFeedbackListener can be notified.
    private var onInbound: (@Sendable ([String]) -> Void)?

    /// Invoked with the text of a user message once the server acknowledges it.
    private var onSent: (@Sendable (String) -> Void)?

    // MARK: - Subscription

    func setChangeHandler(_ handler: (@Sendable ([ChatMessage]) -> Void)?) {
        onChange = handler
    }

    func setInboundHandler(_ handler: (@Sendable ([String]) -> Void)?) {
        onInbound = handler
    }

    func setSentHandler(_ handler: (@Sendable (String) -> Void)?) {
        onSent = handler
    }

    func snapshot() -> [ChatMessage] {
        messages
    }

    // MARK: - Chat visibility → poll lifecycle

    func onChatOpened() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollOnce()
                try? await Task.sleep(nanoseconds: ChatManager.pollIntervalNanos)
            }
        }
    }

    func onChatClosed() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Polling

    func pollOnce() async {
        let till = messages.compactMap { $0.timeReceived }.max().map(ISO8601DateParsing.string(from:)) ?? ""
        do {
            let received = try await api.pollMessages(since: "now", till: till, limit: nil)
            merge(received)
        } catch {
            // Transient poll failure — try again next tick.
        }
    }

    private func merge(_ received: [FeedbackReceivedMessage]) {
        guard !received.isEmpty else { return }
        var changed = false
        var newInboundTexts: [String] = []
        for item in received {
            if let index = messages.firstIndex(where: { $0.id == item.id }) {
                messages[index] = ChatMessage(server: item)
            } else {
                let message = ChatMessage(server: item)
                messages.append(message)
                if !message.isUser {
                    newInboundTexts.append(message.message)
                }
            }
            changed = true
        }
        if changed {
            messages.sort { $0.timeSent < $1.timeSent }
            notify()
            if !newInboundTexts.isEmpty {
                onInbound?(newInboundTexts)
            }
        }
    }

    // MARK: - Sending (optimistic + pending retry)

    func send(text: String, userEmail: String?, userName: String?) async {
        let localId = UUID().uuidString
        let now = Date()
        messages.append(ChatMessage(id: localId,
                                    message: text,
                                    type: .user,
                                    timeSent: now,
                                    timeReceived: nil,
                                    isDelivered: false,
                                    isRead: true))
        // Optimistic render happens here, before the (awaited) network round-trip below.
        notify()
        await deliver(localId: localId, text: text, createdOn: now,
                      userEmail: userEmail, userName: userName)
    }

    private func deliver(localId: String, text: String, createdOn: Date,
                         userEmail: String?, userName: String?) async {
        do {
            let sent = try await api.sendMessage(text: text,
                                                 createdOnISO: ISO8601DateParsing.string(from: createdOn),
                                                 userEmail: userEmail,
                                                 userName: userName)
            if let index = messages.firstIndex(where: { $0.id == localId }) {
                messages[index] = ChatMessage(server: sent)
                notify()
            }
            onSent?(text)
        } catch {
            // Leave the message pending (isDelivered == false); the next flush retries it.
        }
    }

    /// Retry every still-undelivered user message (call on connectivity restored / poll tick).
    func flushPending(userEmail: String?, userName: String?) async {
        let pending = messages.filter { !$0.isDelivered && $0.isUser }
        for message in pending {
            await deliver(localId: message.id, text: message.message, createdOn: message.timeSent,
                          userEmail: userEmail, userName: userName)
        }
    }

    // MARK: - Read state

    func markAsRead() async {
        let unreadServerIds = messages.filter { !$0.isUser && !$0.isRead }.map { $0.id }
        guard !unreadServerIds.isEmpty else { return }
        for index in messages.indices where !messages[index].isUser {
            messages[index].isRead = true
        }
        notify()
        try? await api.markAsRead(ids: unreadServerIds)
    }

    private func notify() {
        let snapshot = messages
        store.save(snapshot)
        onChange?(snapshot)
    }

#if DEBUG
    /// Test hook (host UI tests only): reset the thread to a known state — in memory *and* on
    /// disk, and re-render — so runs are isolated regardless of the shared instance persisting
    /// across test launches. Compiled out of release builds.
    func resetForTesting(seed: [ChatMessage]) {
        messages = seed
        notify()
    }
#endif
}
