//
//  BugseeFeedback.swift
//  BugseeFeedback
//
//  Copyright © 2026 Bugsee. All rights reserved.
//

import Foundation
import UIKit
import SwiftUI
import Bugsee

/// The Feedback add-on's extension facade. It plugs into the core SDK's extension registry
/// (`Bugsee.registerExt(_:)`), is driven through the core lifecycle (`launch`/`stop`), and
/// is retrieved by the host via `Bugsee.ext(BugseeFeedback.self) as? BugseeFeedbackExtension`.
/// Mirrors Android's `BugseeFeedback : Feedback`.
@objc public final class BugseeFeedback: NSObject, Extension, BugseeFeedbackExtension, @unchecked Sendable {

    /// The shared add-on instance registered with the core SDK.
    @objc public static let shared = BugseeFeedback()

    private var isLaunched = false
    private weak var listener: BugseeFeedbackListener?
    private var greeting: String?

    private override init() {
        super.init()
    }

    // MARK: - Registration

    /// Register the Feedback add-on with the core SDK. Invoked automatically on load where
    /// possible (see the ObjC auto-register shim); hosts may also call it explicitly.
    @objc public static func register() {
        Bugsee.registerExt(shared)
    }

    // MARK: - Extension (core lifecycle)

    public var type: AnyClass { BugseeFeedback.self }

    public func launch(withOptions options: BGSOptionsContainer) {
        guard !isLaunched else { return }
        isLaunched = true
        // P3+: start ChatManager, prefill email from the user identifier, etc.
    }

    public func stop() {
        isLaunched = false
        // P3+: stop polling and tear down the chat engine.
    }

    // MARK: - BugseeFeedbackExtension (public API)

    @objc public func showFeedbackUI() {
        let greeting = self.greeting
        // Attribute outgoing messages to the host's user identifier (Android parity: the
        // feedback thread prefills the reporter's email from the SDK user identity).
        let userEmail = Bugsee.getUserIdentifier()
        DispatchQueue.main.async {
            guard let presenter = Self.topViewController() else { return }
            let content: UIViewController
            if #available(iOS 15.0, *) {
                // Modern path: SwiftUI chat.
                content = UIHostingController(rootView: FeedbackChatView(userEmail: userEmail, userName: nil, greeting: greeting))
            } else {
                // iOS 13–14 fallback: UIKit chat (SwiftUI's ScrollViewReader/onChange/etc.
                // aren't available before iOS 15).
                content = FeedbackChatViewController(greeting: greeting, userEmail: userEmail)
            }
            content.title = "Feedback"
            let closeButton = UIBarButtonItem(
                barButtonSystemItem: .close, target: content, action: #selector(UIViewController.bugseeFeedbackDismiss))
            closeButton.accessibilityIdentifier = FeedbackChatAccessibility.close
            content.navigationItem.leftBarButtonItem = closeButton
            let navigation = UINavigationController(rootViewController: content)
            presenter.present(navigation, animated: true)
        }
    }

    /// Find the top-most presentable view controller across the active window scene.
    private static func topViewController() -> UIViewController? {
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        var top = keyWindow?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }

    @objc public func setGreeting(_ greeting: String?) {
        self.greeting = greeting
    }

    @objc public func setListener(_ listener: BugseeFeedbackListener?) {
        self.listener = listener
        guard listener != nil else {
            Task {
                await ChatManager.shared.setInboundHandler(nil)
                await ChatManager.shared.setSentHandler(nil)
            }
            return
        }
        let inbound: @Sendable ([String]) -> Void = { [weak self] texts in
            DispatchQueue.main.async { self?.listener?.onNewMessagesReceived(texts) }
        }
        let sent: @Sendable (String) -> Void = { [weak self] text in
            DispatchQueue.main.async { self?.listener?.onNewMessageSent(text) }
        }
        Task {
            await ChatManager.shared.setInboundHandler(inbound)
            await ChatManager.shared.setSentHandler(sent)
        }
    }
}

private extension UIViewController {
    @objc func bugseeFeedbackDismiss() {
        dismiss(animated: true)
    }
}
