//
//  ChatViewModel.swift
//  BugseeFeedback
//
//  Copyright © 2026 Bugsee. All rights reserved.
//

import Foundation

/// Main-actor bridge between the `ChatManager` actor and the SwiftUI chat view: mirrors the
/// engine's message list into `@Published` state and forwards user actions back to the actor.
@available(iOS 15.0, *)
@MainActor
final class ChatViewModel: ObservableObject {

    @Published private(set) var messages: [ChatMessage] = []
    @Published var draft: String = ""

    private let manager = ChatManager.shared
    private var userEmail: String?
    private var userName: String?

    func configure(userEmail: String?, userName: String?) {
        self.userEmail = userEmail
        self.userName = userName
    }

    func onAppear() {
        Task {
            await manager.setChangeHandler { [weak self] updated in
                Task { @MainActor in self?.messages = updated }
            }
            messages = await manager.snapshot()
            await manager.onChatOpened()
            await manager.markAsRead()
        }
    }

    func onDisappear() {
        Task {
            await manager.onChatClosed()
            await manager.setChangeHandler(nil)
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
