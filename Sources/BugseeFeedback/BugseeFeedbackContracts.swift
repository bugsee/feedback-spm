//
//  BugseeFeedbackContracts.swift
//  BugseeFeedback
//
//  Copyright © 2026 Bugsee. All rights reserved.
//
//  The public contract of the Feedback add-on. Mirrors the Android feedback module's
//  `contracts/feedback` + `contracts/extensions/Feedback` types. These are standalone
//  value/protocol types with no dependency on core internals — the host app interacts
//  with the feature through them after retrieving the extension via
//  `Bugsee.ext(BugseeFeedback.self)`.
//

import Foundation

/// The origin of a feedback message. Ordinals match Android's `FeedbackMessageType`.
/// `@objc` so the type is usable from Objective-C hosts.
@objc public enum BugseeFeedbackMessageType: Int, Sendable, Codable {
    case user = 1
    case server = 2
    case notification = 3
}

/// A single feedback message surfaced to the host app (Swift hosts). Not part of the
/// `@objc` callback surface — the listener callbacks below deliver plain strings, matching
/// Android's `FeedbackListener`, so this stays a Swift value protocol.
public protocol BugseeFeedbackMessage {
    var message: String { get }
    var type: BugseeFeedbackMessageType { get }
    var timeSent: Date { get }
    var timeReceived: Date? { get }
}

/// Callbacks delivered to the host app as feedback activity happens. Mirrors Android's
/// `FeedbackListener`. `@objc` so Objective-C hosts can implement it.
@objc public protocol BugseeFeedbackListener: AnyObject {
    /// New inbound messages arrived (text only, matching Android's callback shape).
    func onNewMessagesReceived(_ messages: [String])
    /// A message was successfully sent by the user.
    func onNewMessageSent(_ message: String)
}

/// The public API of the Feedback add-on, retrieved from the core SDK's extension registry:
/// `Bugsee.ext(BugseeFeedback.self) as? BugseeFeedbackExtension` (Swift) or
/// `(id<BugseeFeedbackExtension>)[Bugsee ext:BugseeFeedback.class]` (Objective-C). Mirrors
/// Android's `contracts/extensions/Feedback` interface. `@objc` for ObjC hosts.
@objc public protocol BugseeFeedbackExtension {
    /// Present the in-app feedback / chat UI.
    func showFeedbackUI()
    /// Set the default greeting shown at the top of an empty conversation.
    func setGreeting(_ greeting: String?)
    /// Register (or clear) the listener that receives feedback callbacks.
    func setListener(_ listener: BugseeFeedbackListener?)
}
