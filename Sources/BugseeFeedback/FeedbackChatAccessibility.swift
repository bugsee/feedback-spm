//
//  FeedbackChatAccessibility.swift
//  BugseeFeedback
//
//  Copyright © 2026 Bugsee. All rights reserved.
//
//  Stable accessibility identifiers for the feedback chat UI (`FeedbackChatView`), for the
//  XCUITest queries. The raw string values are the contract with the UI-test target (which
//  can't import this module) — keep them in sync with the test.
//

import Foundation

enum FeedbackChatAccessibility {
    /// The message-composer text input.
    static let input = "bugsee.feedback.input"
    /// The send button.
    static let send = "bugsee.feedback.send"
    /// The navigation-bar close button.
    static let close = "bugsee.feedback.close"
    /// A message bubble authored by the local user.
    static let userMessage = "bugsee.feedback.message.user"
    /// A message bubble from the developer/server side.
    static let serverMessage = "bugsee.feedback.message.server"
    /// The e-mail screen's text input.
    static let emailInput = "bugsee.feedback.email.input"
    /// The e-mail screen's Continue button.
    static let emailContinue = "bugsee.feedback.email.continue"
    /// The e-mail screen's Skip button.
    static let emailSkip = "bugsee.feedback.email.skip"
}
