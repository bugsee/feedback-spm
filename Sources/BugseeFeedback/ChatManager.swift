//
//  ChatManager.swift
//  BugseeFeedback
//
//  Copyright © 2026 Bugsee. All rights reserved.
//

import Foundation

/// The feedback chat engine and single source of truth: the message list, the poll loop
/// (running only while the chat UI is visible — never in the background), and optimistic
/// send with pending-delivery retry. An `actor`, so all message-list mutation is
/// serialized without explicit locks.
actor ChatManager {

    static let shared = ChatManager()

    private let api: FeedbackApi
    private let store: FeedbackStoring
    private var messages: [ChatMessage]
    private var pollTask: Task<Void, Never>?
    /// The two independent conditions for polling. The chat being on screen is not
    /// enough: the host can stop Bugsee while it is, and a stopped SDK must not keep
    /// reaching the network.
    private var isChatVisible = false
    private var isSuspended = false
    /// The identity of the most recent `send`, used to attribute a flush after `resume()`.
    ///
    /// One field, not per-message state: two pending messages composed under different
    /// identities both flush as the later one, and messages rehydrated from disk in a new
    /// process flush without one. Encoding it per message would change the persisted
    /// `ChatMessage` format, which is not worth doing for the window this covers.
    private var lastSendIdentity: (email: String?, name: String?)?
    /// Local ids with a POST already in flight. `deliver` releases the actor at its
    /// `await`, so without this a stop/resume inside that window lets `flushPending`
    /// pick the same still-undelivered message up and send it twice.
    private var inFlight: Set<String> = []

    /// Dependencies default to the production server API + on-disk store; tests inject stubs.
    init(api: FeedbackApi = FeedbackServerApi(), store: FeedbackStoring = FeedbackStore()) {
        self.api = api
        self.store = store
        // Rehydrate the thread (including still-undelivered user messages) from disk.
        messages = store.load()
    }

    /// Poll cadence while the chat is open (10 seconds).
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

    // MARK: - Poll lifecycle

    func onChatOpened() {
        isChatVisible = true
        startPollingIfNeeded()
    }

    func onChatClosed() {
        isChatVisible = false
        stopPolling()
    }

    /// The core SDK stopped. Tracked separately from visibility so that a chat left on
    /// screen across a stop resumes by itself when the SDK is launched again, instead of
    /// waiting for the view to reappear.
    func suspend() {
        isSuspended = true
        stopPolling()
    }

    /// The core SDK launched. Anything the user did while it was stopped is delivered
    /// now -- that is the other half of `stop()` leaving the thread on disk rather than
    /// discarding it.
    func resume() async {
        isSuspended = false
        startPollingIfNeeded()
        await flushPending(userEmail: lastSendIdentity?.email,
                           userName: lastSendIdentity?.name)
        // Read state deferred by `markAsRead()` while suspended. Only for a chat that is
        // still on screen: marking read is a claim that the user saw the messages, and
        // nothing else calls `markAsRead()` again for a chat left open across a stop.
        if isChatVisible {
            await markAsRead()
        }
    }

    private func startPollingIfNeeded() {
        guard isChatVisible, !isSuspended, pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollOnce()
                try? await Task.sleep(nanoseconds: ChatManager.pollIntervalNanos)
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Polling

    func pollOnce() async {
        // The poll task can clear `Task.isCancelled` and then wait on the actor while
        // `suspend()` runs, so the cancellation alone does not keep it off the network.
        guard !isSuspended else { return }
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
        lastSendIdentity = (userEmail, userName)
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
        // A stopped SDK makes no requests. The message stays pending and on disk, exactly
        // as it would after a network failure, and `resume()` flushes it. This is the one
        // gate that covers both `send` and `flushPending`, since both deliver through here.
        guard !isSuspended else { return }
        guard inFlight.insert(localId).inserted else { return }
        defer { inFlight.remove(localId) }
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
        // Deliberately does not mark locally either while suspended. Marking locally and
        // skipping only the request would leave nothing unread to report once the SDK is
        // running again, so the server would never learn -- the read state would be lost
        // rather than deferred.
        guard !isSuspended else { return }
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
    /// Test seam (host tests only): the suspension half of the poll gate, which is
    /// otherwise only observable through whether a network call happens — and the facade
    /// drives it on `ChatManager.shared`, whose api cannot be stubbed.
    var isSuspendedForTesting: Bool { isSuspended }

    /// Test hook (host UI tests only): reset the thread to a known state — in memory *and* on
    /// disk, and re-render — so runs are isolated regardless of the shared instance persisting
    /// across test launches. Compiled out of release builds.
    func resetForTesting(seed: [ChatMessage]) {
        messages = seed
        notify()
    }
#endif
}
