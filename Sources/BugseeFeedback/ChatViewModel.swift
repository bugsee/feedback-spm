//
//  ChatViewModel.swift
//  BugseeFeedback
//
//  Copyright © 2026 Bugsee. All rights reserved.
//

import Foundation

/// Main-actor bridge between the `ChatManager` actor and the SwiftUI chat view: mirrors the
/// engine's message list into `@Published` state and forwards user actions back to the actor.
@MainActor
final class ChatViewModel: ObservableObject {

    @Published private(set) var messages: [ChatMessage] = []
    @Published var draft: String = ""

    private let manager = ChatManager.shared
    private var userEmail: String?
    private var userName: String?
    /// Runs appear and disappear work in call order. Two unstructured Tasks have no ordering
    /// between them, so a quick disappear then appear (a pushed screen popped right back)
    /// could clear the change handler and close the chat after the appear set them up,
    /// leaving the chat on screen with no updates and no polling.
    private var lifecycleTask: Task<Void, Never>?

    func configure(userEmail: String?, userName: String?) {
        self.userEmail = userEmail
        self.userName = userName
    }

    func onAppear() {
        // The outer capture is explicit so it does not silently strengthen the `[weak self]`
        // below: that inner closure is stored on the `ChatManager` actor and outlives this
        // task, so it must not keep the view model alive.
        enqueueLifecycle { [weak self] in
            guard let self else { return }
            await manager.setChangeHandler { [weak self] updated in
                Task { @MainActor in self?.messages = updated }
            }
            messages = await manager.snapshot()
            await manager.onChatOpened()
            await manager.markAsRead()
        }
    }

    func onDisappear() {
        // Captures the manager, not the view model: closing the chat must run even if the
        // view model is gone by then, or polling would go on with nothing on screen.
        let manager = manager
        enqueueLifecycle {
            await manager.onChatClosed()
            await manager.setChangeHandler(nil)
        }
    }

    private func enqueueLifecycle(_ work: @escaping @MainActor @Sendable () async -> Void) {
        let previous = lifecycleTask
        lifecycleTask = Task {
            await previous?.value
            await work()
        }
    }

    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        let email = userEmail
        let name = userName
        Task { await manager.send(text: text, userEmail: email, userName: name) }
    }
}
