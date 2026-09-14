//
//  FeedbackChatView.swift
//  BugseeFeedback
//
//  Copyright © 2026 Bugsee. All rights reserved.
//

import SwiftUI

/// The in-app feedback chat surface. Mirrors Android's Compose `FeedbackApp`: a scrolling
/// message list driven by the `ChatManager` (via `ChatViewModel`) plus a message composer.
@available(iOS 15.0, *)
public struct FeedbackChatView: View {

    @StateObject private var viewModel = ChatViewModel()

    private let userEmail: String?
    private let userName: String?
    private let greeting: String?

    public init(userEmail: String? = nil, userName: String? = nil, greeting: String? = nil) {
        self.userEmail = userEmail
        self.userName = userName
        self.greeting = greeting
    }

    public var body: some View {
        // NB: no `.accessibilityIdentifier` on this root container — in SwiftUI a container's
        // identifier propagates to and overrides every descendant's own identifier, which would
        // clobber the input/send/message identifiers below. The presented nav bar ("Feedback")
        // is the "screen is up" signal for tests instead.
        VStack(spacing: 0) {
            messageList
            Divider()
            composer
        }
        .onAppear {
            viewModel.configure(userEmail: userEmail, userName: userName)
            viewModel.onAppear()
        }
        .onDisappear { viewModel.onDisappear() }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if let greeting = greeting, viewModel.messages.isEmpty {
                        Text(greeting)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 12)
                    }
                    ForEach(viewModel.messages) { message in
                        MessageRow(message: message).id(message.id)
                    }
                }
                .padding()
            }
            .onChange(of: viewModel.messages.count) { _ in
                guard let last = viewModel.messages.last else { return }
                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("Message", text: $viewModel.draft)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .accessibilityIdentifier(FeedbackChatAccessibility.input)
            Button(action: viewModel.send) {
                Image(systemName: "arrow.up.circle.fill").font(.title2)
            }
            .disabled(viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier(FeedbackChatAccessibility.send)
        }
        .padding()
    }
}

@available(iOS 15.0, *)
private struct MessageRow: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.isUser { Spacer(minLength: 40) }
            Text(message.message)
                .padding(10)
                .background(message.isUser ? Color.accentColor.opacity(0.18) : Color.gray.opacity(0.15))
                .cornerRadius(14)
                .opacity(message.isDelivered ? 1.0 : 0.5)
                .accessibilityIdentifier(message.isUser
                    ? FeedbackChatAccessibility.userMessage
                    : FeedbackChatAccessibility.serverMessage)
            if !message.isUser { Spacer(minLength: 40) }
        }
    }
}
