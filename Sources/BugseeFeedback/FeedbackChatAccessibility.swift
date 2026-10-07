//
//  FeedbackChatAccessibility.swift
//  BugseeFeedback
//
//  Copyright © 2026 Bugsee. All rights reserved.
//
//  Stable accessibility identifiers for the feedback chat UI, shared by both the SwiftUI
//  (`FeedbackChatView`) and UIKit (`FeedbackChatViewController`) presentations so a single
//  set of XCUITest queries can drive either path. The raw string values are the contract with
//  the UI-test target (which can't import this module) — keep them in sync with the test.
//

import Foundation

enum FeedbackChatAccessibility {
    /// The chat surface root (present ⇒ the feedback UI is on screen).
    static let screen = "bugsee.feedback.screen"
    /// The message-composer text input.
    static let input = "bugsee.feedback.input"
    /// The send button.
    static let send = "bugsee.feedback.send"
    /// The navigation-bar close button.
    static let close = "bugsee.feedback.close"
    /// The scrolling message list.
    static let list = "bugsee.feedback.list"
    /// A message bubble authored by the local user.
    static let userMessage = "bugsee.feedback.message.user"
    /// A message bubble from the developer/server side.
    static let serverMessage = "bugsee.feedback.message.server"
}
