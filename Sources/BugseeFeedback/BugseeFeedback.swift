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
@objc public final class BugseeFeedback: NSObject, Extension, BugseeFeedbackExtension, @unchecked Sendable {

    /// The shared add-on instance registered with the core SDK.
    @objc public static let shared = BugseeFeedback()

    /// Guards every mutable field below.
    ///
    /// This is a singleton whose entry points are public and carry no threading
    /// requirement, and the core does not deliver them on one thread. `stop` arrives on
    /// the main thread; `launch` arrives on whichever thread called `register()` when
    /// registration happens after the SDK is already running. A host that registers late
    /// and off the main thread therefore has the two running concurrently.
    private let stateLock = NSLock()

    /// Only whether *this instance* has already seen `launch(withOptions:)`, so the
    /// resume is not applied twice. It deliberately does not gate `stop()`.
    private var isLaunched = false
    /// Serialises the hops onto `ChatManager`. Two unstructured `Task`s started from one
    /// turn of the run loop have no ordering between them, so a launch immediately
    /// followed by a stop could otherwise leave the engine resumed.
    private var lifecycleTask: Task<Void, Never>?
    private weak var listener: BugseeFeedbackListener?
    private var greeting: String?

    private func withState<T>(_ body: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body()
    }

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
        // Test and set together: read and write as separate steps would let a late,
        // off-main `register()` and the ordinary launch both pass the guard.
        let wasLaunched = withState { () -> Bool in
            if isLaunched { return true }
            isLaunched = true
            return false
        }
        guard !wasLaunched else { return }
        // Nothing else to start here. `ChatManager` is created on first use and rehydrates
        // the thread from disk itself, and polling is driven by the chat being on screen,
        // not by launch -- this only lifts the suspension a previous `stop()` applied, so a
        // chat left open across a stop/launch cycle starts polling again on its own, and
        // anything sent while it was stopped is flushed.
        enqueueLifecycle { await ChatManager.shared.resume() }
    }

    public func stop() {
        // Only a genuine stop suspends the engine, and `BugseeStatusStopping` is what
        // identifies one: `Bugsee.stop` puts the SDK into that state before it tears
        // anything down. The extension is also told to stop for reasons that are not a
        // stop of the SDK, and suspending for those would leave the chat unable to poll
        // or deliver with nothing to bring it back.
        //
        // Matching `Stopping` exactly, rather than "anything except `Launched`", is what
        // makes that correct whenever this is called. `Bugsee.launch` reaches `Launched`
        // asynchronously, so there is a window in which the SDK is starting rather than
        // stopping -- also not `Launched`, and also not a reason to suspend.
        guard coreStatus() == BugseeStatusStopping else { return }

        // No `guard isLaunched`. A host that registers AFTER `Bugsee.launch` may never
        // receive `launch(withOptions:)` at all -- launch is handed to the extensions
        // registered at that moment, and a later registration only catches up once the
        // SDK reports `Launched`, which it does not yet during start-up. Gating on
        // `isLaunched` would make `stop()` a no-op for exactly those hosts and leave the
        // engine running against a stopped SDK, which is what this path exists to
        // prevent. Register before launching and the question does not arise.
        withState { isLaunched = false }
        // Halt the poll loop. Without this it keeps reaching the network every 10 seconds
        // for as long as the chat stays on screen, because the loop is otherwise torn down
        // only by the view disappearing -- a stopped SDK making requests.
        //
        // The cached thread and the store are deliberately left alone: stopping Bugsee is
        // not the user discarding their conversation, and an undelivered message must
        // survive to be retried after the next launch.
        enqueueLifecycle { await ChatManager.shared.suspend() }
    }

    /// The core's lifecycle status, as `stop()` reads it.
    private func coreStatus() -> BugseeStatus? {
        #if DEBUG
        if let statusForTesting { return statusForTesting }
        #endif
        return Bugsee.sharedInstance()?.status
    }

    #if DEBUG
    private var _statusForTesting: BugseeStatus?
    /// Test seam (host tests only). The tests run inside a launched Bugsee, where the
    /// real status makes every `stop()` look like a recording pause and return early.
    var statusForTesting: BugseeStatus? {
        get { withState { _statusForTesting } }
        set { withState { _statusForTesting = newValue } }
    }
    #endif

    /// Run lifecycle work on `ChatManager` in call order. Chaining onto the previous task
    /// is what supplies the happens-before two independent `Task`s lack.
    private func enqueueLifecycle(_ work: @escaping @Sendable () async -> Void) {
        // Read and replace under one lock. Unsynchronised, two threads read the same
        // `previous` and each overwrites the other's assignment, which drops a link out
        // of the chain -- losing the very ordering this exists to provide.
        withState {
            let previous = lifecycleTask
            lifecycleTask = Task {
                await previous?.value
                await work()
            }
        }
    }

    // MARK: - BugseeFeedbackExtension (public API)

    @objc public func showFeedbackUI() {
        let greeting = withState { self.greeting }
        // Attribute outgoing messages to the host's user identifier: the feedback thread
        // prefills the reporter's email from the SDK user identity.
        let userEmail = Bugsee.getUserIdentifier()
        // Hops to the main actor rather than `DispatchQueue.main.async` so the UIKit work
        // below is main-actor-isolated for the compiler, not only at runtime.
        Task { @MainActor in
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
    @MainActor
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
        withState { self.greeting = greeting }
    }

    @objc public func setListener(_ listener: BugseeFeedbackListener?) {
        withState { self.listener = listener }
        guard listener != nil else {
            Task {
                await ChatManager.shared.setInboundHandler(nil)
                await ChatManager.shared.setSentHandler(nil)
            }
            return
        }
        // The handlers read the listener through `currentListener` rather than capturing
        // the argument: the host may replace it later, and these closures live on the
        // actor until it does.
        let inbound: @Sendable ([String]) -> Void = { [weak self] texts in
            guard let self else { return }
            DispatchQueue.main.async { self.currentListener?.onNewMessagesReceived(texts) }
        }
        let sent: @Sendable (String) -> Void = { [weak self] text in
            guard let self else { return }
            DispatchQueue.main.async { self.currentListener?.onNewMessageSent(text) }
        }
        Task {
            await ChatManager.shared.setInboundHandler(inbound)
            await ChatManager.shared.setSentHandler(sent)
        }
    }

    /// The host's listener, read under the lock. Held weakly, so this can go nil at any
    /// point; the strong reference the callbacks above take is deliberately short-lived.
    private var currentListener: BugseeFeedbackListener? {
        withState { listener }
    }
}

private extension UIViewController {
    @objc func bugseeFeedbackDismiss() {
        dismiss(animated: true)
    }
}
