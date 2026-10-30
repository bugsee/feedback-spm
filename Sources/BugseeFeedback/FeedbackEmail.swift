//
//  FeedbackEmail.swift
//  BugseeFeedback
//
//  Copyright © 2026 Bugsee. All rights reserved.
//

import Foundation

/// The contact e-mail the chat asks for once, as Android's feedback does, and whether it has
/// been asked. Kept in `UserDefaults`, so it survives relaunches; the message cache under
/// Caches does not have to.
struct FeedbackEmailPreferences {

    private static let emailKey = "com.bugsee.feedback.email"
    private static let requestedKey = "com.bugsee.feedback.email-requested"
    /// Set by the 6.x feedback the first time it showed its e-mail screen.
    private static let legacyAskedKey = "bugsee_asked_for_email"

    private let defaults: UserDefaults

    /// - Parameter defaults: tests pass a suite of their own.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The e-mail the user gave on the screen.
    var email: String? {
        defaults.string(forKey: Self.emailKey)
    }

    /// Whether the e-mail screen is settled: answered with Continue or Skip (here or by the
    /// 6.x feedback), or made unnecessary by an e-mail-shaped user identifier. It is not shown
    /// again once it is.
    var isRequested: Bool {
        defaults.bool(forKey: Self.requestedKey) || defaults.bool(forKey: Self.legacyAskedKey)
    }

    func save(email: String) {
        defaults.set(email.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Self.emailKey)
        defaults.set(true, forKey: Self.requestedKey)
    }

    func skip() {
        defaults.set(true, forKey: Self.requestedKey)
    }

    /// A user identifier with an `@` spares the screen, as on Android, unless the user has
    /// already answered it. It is not copied into `email`: messages carry the identifier as it
    /// is when they are sent, so a host that switches users does not send the previous one's.
    func prefill(fromUserIdentifier identifier: String?) {
        guard !isRequested,
              let identifier = identifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              identifier.contains("@") else { return }
        skip()
    }

    /// The e-mail a message is sent with: the one the user gave, else the user identifier,
    /// which is what every message carried before the screen existed.
    func sendingEmail(userIdentifier: String?) -> String? {
        email ?? userIdentifier
    }

    /// Android's rough check: something, `@`, something, a dot, something.
    static func isValid(_ email: String) -> Bool {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
            .range(of: #"^.+@.+\..+$"#, options: .regularExpression) != nil
    }

    #if DEBUG
    /// Test seam: back to a fresh install.
    func resetForTesting() {
        defaults.removeObject(forKey: Self.emailKey)
        defaults.removeObject(forKey: Self.requestedKey)
        defaults.removeObject(forKey: Self.legacyAskedKey)
    }
    #endif
}
