//
//  FeedbackEmailView.swift
//  BugseeFeedback
//
//  Copyright © 2026 Bugsee. All rights reserved.
//

import SwiftUI
import Bugsee

/// The feedback UI's root: the e-mail screen until it is settled, then the chat.
struct FeedbackRootView: View {

    private let greeting: String?
    private let preferences: FeedbackEmailPreferences
    /// Called once the e-mail screen gives way to the chat.
    let onEmailSettled: () -> Void
    @State private var asksForEmail: Bool
    /// The identifier the chat sends with when no e-mail was given: the one the UI opened
    /// with, read again when the e-mail screen is settled, since the host may have switched
    /// users while the screen was up.
    @State private var userIdentifier: String?

    init(greeting: String?,
         userIdentifier: String?,
         preferences: FeedbackEmailPreferences,
         asksForEmail: Bool,
         onEmailSettled: @escaping () -> Void) {
        self.greeting = greeting
        self.preferences = preferences
        self.onEmailSettled = onEmailSettled
        _asksForEmail = State(initialValue: asksForEmail)
        _userIdentifier = State(initialValue: userIdentifier)
    }

    var body: some View {
        if asksForEmail {
            FeedbackEmailView(preferences: preferences) {
                userIdentifier = Bugsee.getUserIdentifier()
                asksForEmail = false
                onEmailSettled()
            }
        } else {
            // Built once the screen is settled, so it sends with the e-mail given there.
            FeedbackChatView(userEmail: preferences.sendingEmail(userIdentifier: userIdentifier),
                             userName: nil,
                             greeting: greeting)
        }
    }
}

/// Asks once for an e-mail to be notified at when the reply is available, as Android's
/// feedback does and the 6.x iOS feedback did. Painted with the `feedbackEmail*` keys of
/// `BugseeTheme`; `BugseeFeedback.chatController` picks the interface style from its
/// background while it is shown.
struct FeedbackEmailView: View {

    let preferences: FeedbackEmailPreferences
    let onDone: () -> Void
    @State private var email = ""

    var body: some View {
        let theme = Bugsee.getAppearance()
        // Scrolls so Skip stays reachable at large Dynamic Type sizes or in landscape with the
        // keyboard up.
        ScrollView {
            content(theme: theme, isValid: FeedbackEmailPreferences.isValid(email))
        }
        .background(Color(uiColor: theme.feedbackEmailBackgroundColor).ignoresSafeArea())
    }

    private func content(theme: BugseeTheme, isValid: Bool) -> some View {
        VStack(spacing: 16) {
            Text("Get notified by email when the reply is available.")
                .multilineTextAlignment(.center)
                .padding(.top, 32)
            TextField("name@example.com", text: $email)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .submitLabel(.continue)
                .onSubmit(continueTapped)
                .accessibilityIdentifier(FeedbackChatAccessibility.emailInput)
            Button(action: continueTapped) {
                Text("CONTINUE")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundColor(.white)
                    .background(Color(uiColor: isValid
                        ? theme.feedbackEmailContinueActiveColor
                        : theme.feedbackEmailContinueNotActiveColor))
                    .cornerRadius(8)
            }
            .disabled(!isValid)
            .accessibilityIdentifier(FeedbackChatAccessibility.emailContinue)
            Button(action: skipTapped) {
                Text("SKIP")
                    .padding(.vertical, 8)
                    .foregroundColor(Color(uiColor: theme.feedbackEmailSkipColor))
            }
            .accessibilityIdentifier(FeedbackChatAccessibility.emailSkip)
        }
        .padding(.horizontal, 24)
    }

    private func continueTapped() {
        guard FeedbackEmailPreferences.isValid(email) else { return }
        preferences.save(email: email)
        onDone()
    }

    private func skipTapped() {
        preferences.skip()
        onDone()
    }
}
