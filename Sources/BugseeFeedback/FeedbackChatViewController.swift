//
//  FeedbackChatViewController.swift
//  BugseeFeedback
//
//  Copyright © 2026 Bugsee. All rights reserved.
//

import UIKit

/// UIKit feedback chat used on iOS 13–14, where the SwiftUI `FeedbackChatView`
/// (ScrollViewReader / onChange / LazyVStack, all iOS 15+) isn't available. Same engine
/// (`ChatManager`) and behaviour as the SwiftUI path — the core SDK supports iOS 13+, so the
/// add-on's UI must too.
@MainActor
final class FeedbackChatViewController: UIViewController, UITableViewDataSource {

    private let greeting: String?
    private let userEmail: String?
    private var messages: [ChatMessage] = []
    private let manager = ChatManager.shared

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let inputField = UITextField()
    private let sendButton = UIButton(type: .system)
    private let inputBar = UIView()
    private var inputBarBottom: NSLayoutConstraint!

    init(greeting: String?, userEmail: String?) {
        self.greeting = greeting
        self.userEmail = userEmail
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        view.accessibilityIdentifier = FeedbackChatAccessibility.screen
        setupSubviews()
        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardWillChange(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Task {
            await manager.setChangeHandler { [weak self] updated in
                Task { @MainActor in self?.apply(updated) }
            }
            apply(await manager.snapshot())
            await manager.onChatOpened()
            await manager.markAsRead()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        Task {
            await manager.onChatClosed()
            await manager.setChangeHandler(nil)
        }
    }

    // MARK: - State

    private func apply(_ messages: [ChatMessage]) {
        self.messages = messages
        tableView.reloadData()
        guard !messages.isEmpty else { return }
        tableView.scrollToRow(at: IndexPath(row: messages.count - 1, section: 0), at: .bottom, animated: true)
    }

    @objc private func sendTapped() {
        let text = (inputField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputField.text = ""
        Task { await manager.send(text: text, userEmail: userEmail, userName: nil) }
    }

    // MARK: - UITableViewDataSource

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        messages.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "bubble", for: indexPath) as! BubbleCell
        cell.configure(with: messages[indexPath.row])
        return cell
    }

    // MARK: - Layout

    private func setupSubviews() {
        tableView.dataSource = self
        tableView.register(BubbleCell.self, forCellReuseIdentifier: "bubble")
        tableView.separatorStyle = .none
        tableView.allowsSelection = false
        tableView.keyboardDismissMode = .interactive
        tableView.accessibilityIdentifier = FeedbackChatAccessibility.list
        tableView.translatesAutoresizingMaskIntoConstraints = false

        inputBar.backgroundColor = .secondarySystemBackground
        inputBar.translatesAutoresizingMaskIntoConstraints = false

        inputField.placeholder = greeting ?? "Message"
        inputField.borderStyle = .roundedRect
        inputField.returnKeyType = .send
        inputField.delegate = self
        inputField.accessibilityIdentifier = FeedbackChatAccessibility.input
        inputField.translatesAutoresizingMaskIntoConstraints = false

        sendButton.setImage(UIImage(systemName: "arrow.up.circle.fill"), for: .normal)
        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        sendButton.accessibilityIdentifier = FeedbackChatAccessibility.send
        sendButton.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(tableView)
        view.addSubview(inputBar)
        inputBar.addSubview(inputField)
        inputBar.addSubview(sendButton)

        inputBarBottom = inputBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: inputBar.topAnchor),

            inputBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inputBarBottom,

            inputField.leadingAnchor.constraint(equalTo: inputBar.leadingAnchor, constant: 12),
            inputField.topAnchor.constraint(equalTo: inputBar.topAnchor, constant: 8),
            inputField.bottomAnchor.constraint(equalTo: inputBar.bottomAnchor, constant: -8),
            inputField.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),

            sendButton.trailingAnchor.constraint(equalTo: inputBar.trailingAnchor, constant: -12),
            sendButton.centerYAnchor.constraint(equalTo: inputField.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 32),
        ])
    }

    @objc private func keyboardWillChange(_ notification: Notification) {
        guard let frame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
        let overlap = max(0, view.bounds.height - view.safeAreaInsets.bottom - frame.origin.y)
        inputBarBottom.constant = -overlap
        view.layoutIfNeeded()
    }
}

extension FeedbackChatViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        sendTapped()
        return true
    }
}

/// A minimal left/right chat bubble cell.
private final class BubbleCell: UITableViewCell {
    private let bubble = UILabel()
    private var leading: NSLayoutConstraint!
    private var trailing: NSLayoutConstraint!

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        bubble.numberOfLines = 0
        bubble.layer.cornerRadius = 14
        bubble.layer.masksToBounds = true
        bubble.translatesAutoresizingMaskIntoConstraints = false
        // Inset text via layoutMargins on a container-free label using a text container hack:
        bubble.setContentHuggingPriority(.required, for: .vertical)
        contentView.addSubview(bubble)

        leading = bubble.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12)
        trailing = bubble.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12)
        NSLayoutConstraint.activate([
            bubble.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            bubble.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            bubble.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.75),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(with message: ChatMessage) {
        // Pad the text with spaces/newlines-free insets via attributed padding.
        bubble.text = "  \(message.message)  "
        bubble.textColor = message.isUser ? .white : .label
        bubble.backgroundColor = message.isUser ? .systemBlue : .secondarySystemFill
        bubble.alpha = message.isDelivered ? 1.0 : 0.5
        bubble.accessibilityIdentifier = message.isUser
            ? FeedbackChatAccessibility.userMessage
            : FeedbackChatAccessibility.serverMessage
        leading.isActive = !message.isUser
        trailing.isActive = message.isUser
    }
}
