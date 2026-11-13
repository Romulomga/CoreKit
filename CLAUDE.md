# CLAUDE.md

CoreKit is the non-visual base shared by the owner's iOS apps (`~/ReciboJa`, `~/Canetto`, `~/MagicPick`,
`~/homer.app.ios`). The apps had copied the same pieces into each repo — analytics client and Firebase setup, the
StoreKit 2 store, the review prompt, the "store that won't open" check, Homer's navigation layer — and the copies had
already diverged (the ReciboJa and Canetto stores differ by 600+ lines). A fix here reaches every app.

The visual twin is DSKit (`~/DSKit`): anything that draws a component goes there, never here. CoreKit does not depend
on DSKit.

## Decisions (owner interview, 2026-11-13)

- **Repository**: public, `github.com/Romulomga/CoreKit`, MIT. No secrets, no app-specific code or names.
- **Twin by concept of CoreKit-Android** (`~/CoreKit-Android`): when a problem exists on both platforms, the piece has
  the same name and the same rule on both (`Entitlement` with an unknown state, `ReviewGate`, `CollectionPolicy`,
  the navigator that doesn't push the same destination twice). A piece only one platform needs is said so in its doc
  and in the README. A change to a shared concept is evaluated on the other side in the same round.
- **iOS 17**, Swift 6 language mode with complete strict concurrency, Swift Testing for tests.
- **Apps in v0.1**: ReciboJa, Canetto, MagicPick and Homer, all four, navigation included.
- **Modules** (one library product each; an app compiles only what it imports):
  - `CoreKit`: small pure helpers with no other home.
  - `CoreKitNavigation`: Homer's navigation layer, generalized (coordinator with push/sheet/full-screen cover, one
    host per tab, tab bar hidden while pushed, session observer). Login-only requirements (`mainTab`) belong to the
    session observer, not to every destination.
  - `CoreKitAnalytics`: the analytics client protocol, the "debug never collects" policy, `TrackScreen`, and the
    setup entry point that starts the engines the app passes.
  - `CoreKitFirebase` (Firebase Analytics + Crashlytics) and `CoreKitMixpanel`: one module per engine, so an app
    compiles only the SDK it uses. The app imports the engine, passes its keys, and the module does the setup; more
    than one engine can run at once.
  - `CoreKitStore`: StoreKit 2 Pro store, twin of CoreKit-Android's `ProStore`.
  - `CoreKitReview`: when to ask for a review (`ReviewGate`); WHEN in the journey stays in the app.
  - `CoreKitPersistence`: opening the SwiftData store as healthy or degraded, never deleting or replacing the file.
    The recovery screen stays in each app (its copy and support contact are the app's).
  - `CoreKitTesting`: fakes shared by the apps' tests.
- **Distribution**: SwiftPM by URL, apps pin `minorVersion` (never `exactVersion`), like DSKit. Never a local path.
- **Firebase version**: the range lives here (`from: 12.15.0`); bumping Firebase in the apps is a CoreKit release.
- **No CI**: verification is local, before every tag.

## What stays in each app

Event names and their parameters (product decisions), product ids, where the confirmed Pro right is persisted, trial
and purchase analytics, the destination enum and the view for each destination, when to ask for a review, the
recovery screen, and the engine keys (`GoogleService-Info.plist`, Mixpanel token).

## Conventions

- Only what an app uses is `public`. Doc comments in English explain the *why* (the bug the piece prevents), like
  DSKit; no comments that restate the code.
- Nothing app-specific: no product ids, strings, event names, bundle ids or app names.
- Every piece ships with a test that fails without it.
- `@MainActor @Observable` for UI-facing state; async/await only; no Combine, no `ObservableObject`.
- Blank line between logical blocks.
- A new piece enters only when at least two apps need it; otherwise it stays in the app.

## Verify

```sh
xcodebuild -scheme CoreKit-Package -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Release: update `CHANGELOG.md`, commit, tag `x.y.z`, push the tag.
