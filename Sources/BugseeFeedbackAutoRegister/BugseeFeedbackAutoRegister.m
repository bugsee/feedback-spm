//
//  BugseeFeedbackAutoRegister.m
//  BugseeFeedbackAutoRegister
//
//  Copyright © 2026 Bugsee. All rights reserved.
//

#import "BugseeFeedbackAutoRegister.h"

// The Swift half of the add-on. SPM exposes the Swift target's `@objc` surface (including
// `+[BugseeFeedback register]`) as a Clang module we import here.
@import BugseeFeedback;

@implementation BugseeFeedbackAutoRegister

+ (void)load {
    // Register the Feedback add-on with the core SDK before the host's own `+load`/`main`
    // has a chance to launch Bugsee. Registration is idempotent on the core side, so an
    // additional explicit `BugseeFeedback.register()` from the host is harmless.
    [BugseeFeedback register];
}

@end
