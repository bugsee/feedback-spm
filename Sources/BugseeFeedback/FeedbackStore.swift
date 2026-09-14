//
//  FeedbackStore.swift
//  BugseeFeedback
//
//  Copyright © 2026 Bugsee. All rights reserved.
//

import Foundation

/// The persistence contract used by the chat engine, so `ChatManager` can be driven with an
/// in-memory store in tests.
protocol FeedbackStoring {
    func load() -> [ChatMessage]
    func save(_ messages: [ChatMessage])
}

/// Durable, dependency-free persistence for the feedback thread: the cached message list
/// (including still-undelivered user messages, so pending sends survive relaunch) is stored
/// as a single JSON file under Caches. Android backs this with SQLite; a JSON file is
/// sufficient for a single chat thread and keeps the package free of extra dependencies and
/// deployment-target constraints (SwiftData/GRDB can replace it later behind this same API).
struct FeedbackStore: FeedbackStoring {

    private let fileURL: URL

    /// - Parameter directory: the folder to store `messages.json` in. Defaults to
    ///   `Caches/com.bugsee.feedback`; tests pass a temporary directory for isolation.
    init(directory: URL? = nil) {
        let folder = directory ?? {
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            return caches.appendingPathComponent("com.bugsee.feedback", isDirectory: true)
        }()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        self.fileURL = folder.appendingPathComponent("messages.json")
    }

    func load() -> [ChatMessage] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([ChatMessage].self, from: data)) ?? []
    }

    func save(_ messages: [ChatMessage]) {
        guard let data = try? JSONEncoder().encode(messages) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
