//
//  BugseeFeedbackAutoRegister.h
//  BugseeFeedbackAutoRegister
//
//  Copyright © 2026 Bugsee. All rights reserved.
//
//  Zero-touch auto-registration shim for the Feedback add-on. This target exists only to
//  carry an Objective-C `+load` that registers `BugseeFeedback` with the core SDK's
//  extension registry as soon as the image is loaded — Swift classes don't get `+load`,
//  so the registration is driven from Objective-C here.
//
//  This is best-effort: a host that links the package as a static library without `-ObjC`
//  (or `-force_load`) may dead-strip this `+load`-only translation unit, in which case the
//  auto-registration silently does not run. The explicit `BugseeFeedback.register()` call
//  always works and is the guaranteed fallback.
//

#import <Foundation/Foundation.h>

/// Marker class for the auto-registration translation unit. It has no public API; its only
/// purpose is to host the `+load` that calls `[BugseeFeedback register]`.
@interface BugseeFeedbackAutoRegister : NSObject
@end
