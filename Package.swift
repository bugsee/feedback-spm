// swift-tools-version:5.9
//
//  Package.swift
//  BugseeFeedback
//
//  Copyright © 2026 Bugsee. All rights reserved.
//
//  The Bugsee Feedback add-on: an optional, SwiftUI-based in-app feedback/chat
//  module delivered as a separate Swift package on top of the core Bugsee SDK.
//

import PackageDescription

let package = Package(
    name: "BugseeFeedback",
    platforms: [
        // Matches the core SDK's minimum deployment target.
        .iOS(.v15),
    ],
    products: [
        // Both targets are vended: the Swift feature, and a small Objective-C shim whose
        // `+load` registers it with the core SDK automatically. Hosts that prefer explicit
        // control can call `BugseeFeedback.register()` themselves -- registration is
        // idempotent, so doing both is harmless.
        .library(
            name: "BugseeFeedback",
            targets: ["BugseeFeedback", "BugseeFeedbackAutoRegister"]),
    ],
    dependencies: [
        // The core Bugsee SDK: a binary xcframework, vended by the bugsee/spm package.
        //
        // Pinned to exactly one version. Every release of this add-on ships together with
        // the core release of the same version and is built against that core's add-on
        // interface (`Bugsee.SPI`), which is not app API and may change in any core
        // release. A version range would let the core move on its own underneath the add-on.
        .package(url: "https://github.com/bugsee/spm", exact: "7.0.1"),
    ],
    targets: [
        .target(
            name: "BugseeFeedback",
            dependencies: [
                .product(name: "Bugsee", package: "spm"),
            ],
            path: "Sources/BugseeFeedback",
            // Apple reads the privacy manifest from the root of the target's resource
            // bundle. It declares what this add-on collects -- the text a user types into
            // the chat, and the identity those messages are attributed to -- which the
            // core SDK's own manifest does not cover.
            resources: [.copy("PrivacyInfo.xcprivacy")]),
        // The auto-registration shim. It depends on the Swift target so it can
        // `@import BugseeFeedback;` and call `[BugseeFeedback register]` at image load.
        .target(
            name: "BugseeFeedbackAutoRegister",
            dependencies: [
                "BugseeFeedback",
            ],
            path: "Sources/BugseeFeedbackAutoRegister"),
    ]
)
