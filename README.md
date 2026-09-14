# BugseeFeedback

BugseeFeedback is an optional add-on for the [Bugsee](https://github.com/bugsee/spm)
iOS SDK that adds an in-app feedback / chat channel, so your users can send you a
message — with the same session context Bugsee already captures — without leaving
your app.

This is a **beta** release, pinned to a specific version of both packages so your
build stays reproducible.

## Requirements

- iOS 13.0+
- The Bugsee core SDK (added automatically as a dependency below)

## Installation

Add both packages to your `Package.swift`, or via Xcode's Swift Package Manager UI,
pinned to the exact beta version:

```swift
.package(url: "https://github.com/bugsee/spm",          exact: "7.0.0-beta1"),
.package(url: "https://github.com/bugsee/feedback-spm", exact: "7.0.0-beta1"),
```

Then add `Bugsee` and `BugseeFeedback` as dependencies of your app target.

## Usage

Register the add-on once, after you start Bugsee:

```swift
import Bugsee
import BugseeFeedback

Bugsee.launch(token: "<your app token>")
BugseeFeedback.register()
```

Then present the feedback UI wherever makes sense for your app — a settings screen,
a shake gesture, a support button:

```swift
BugseeFeedback.shared.showFeedbackUI()
```

That's it — BugseeFeedback presents a chat screen the user can send messages
through, and you can reply from the Bugsee dashboard.

### Objective-C

The public API is `@objc`-exposed, so it works from Objective-C as well:

```objective-c
@import Bugsee;
@import BugseeFeedback;

[BugseeFeedback register];
[[BugseeFeedback shared] showFeedbackUI];
```

## Feedback and support

This package is part of the Bugsee SDK. For questions or issues, reach out through
[https://www.bugsee.com](https://www.bugsee.com).
