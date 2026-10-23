# 20261023-1002-product-ui-i18n-settings Product-grade UI, languages, account explanations and settings

- **status**: implementing
- **createdAt**: 2026-10-23 10:02
- **approvedAt**: 2026-10-23 09:58 (user, through the gimhq workspace coordinator: auto mode for campaign `l1-0xhhlawj-20261023095300`)
- **relatedTask**: 20261023-1002-product-ui-i18n-settings

## Context

Goal (user, 2026-10-23): the iOS app must align with the approved gim-android
plan `gim-android/docs/plan/20261023-0755-product-ui-i18n-settings.md`:
from demo to a basic product, benchmarked against Signal and Telegram, usable
alone by a 12-year-old. Same six steps, adapted to iOS. Early development
stage: no backward-compatibility work.

Workspace contracts (ledger `gimhq/docs/plan/20261023-0953-clients-product-alignment.md`):

- C1 glossary and writing rules: `gim-android` `docs/glossary.md` (branch `bkd/uxo2xvuo`).
- C2 recovery kit text format and label-independent parser: `gim-android`
  `feature/onboarding/src/main/kotlin/im/g/apps/feature/onboarding/RecoveryKit.kt`
  (branch `bkd/liid6n5a`). A kit written on one client restores on every other.
  The SDK will ship one implementation later; until then iOS implements the
  same format in GIMFeatures.
- C3 languages: en, zh-CN, zh-TW, es.
- C4 settings sections and the "How gim works" explainer text:
  `gim-android` `core/designsystem/src/main/res/values/strings_explainer.xml`
  (branch `bkd/liid6n5a`), same words on every client.
- C6 `Packages/GIMKit` stays Foundation-only (gim-mac consumes it by path).
- C7 account-safety SDK APIs (`gim-client-sdk/docs/plan/20261023-0930-account-safety-features.md`):
  `rotateRecoveryCode()` exists at gim-client-sdk 0fca69d; block, privacy
  switches, mute/pin/archive and avatar follow. Entries stay hidden until the
  API exists.

Current state (main 2e590c8):

- `Packages/GIMKit`: `GIMClientKit` (API mirror, `FakeGimClient`) and
  `GIMFeatures` (view models); builds and tests on Linux and macOS.
  `Packages/GIMUI`: `GIMUI` (SwiftUI/UIKit screens) and `GIMPlatform`.
  App target `GIM/` (`GIMApp.swift`, Notification Service Extension, UI tests).
- No localization: 0 localized strings, no String Catalog, no
  `CFBundleLocalizations`; 52 `Text("...")` literals in GIMUI plus the English
  copy in `GIMFeatures/Common/ErrorPresenter.swift`, `UserLabel.swift`,
  `RelativeDateFormatter.swift`.
- Wording is protocol-level (hub, handle, user ID, recovery code, revoke,
  verified/unverified, primary hub), see `SettingsSheet.swift`, `HubsScreen.swift`,
  `DevicesScreen.swift`, `OnboardingScreen.swift`, `RecoveryCodeScreen.swift`.
- Onboarding (`Packages/GIMUI/Sources/GIMUI/Onboarding`, `Identity/RestoreScreen.swift`)
  asks for the server address first, then create / link / restore. Restore
  needs the user ID and the recovery code typed separately; the recovery code
  screen shows the code alone, once (`recovery.continue`, `recovery.confirm`).
- Settings is the sheet `Packages/GIMUI/Sources/GIMUI/App/SettingsSheet.swift`
  (identity, devices, hubs, session, sign out), opened from a gear button in
  `ChatListScreen.swift` (`chatList.settings`). No profile editing, although
  the API mirror has `setDisplayName`, `claimHandle`, `releaseHandle`.
- Appearance follows the system; `AvatarView` has initials with colors.
- UI tests (`GIM/UITests`) drive the app mostly through accessibility
  identifiers (69 in GIMUI) and a few visible labels ("Delete", "Group Info",
  "You left", "Done", "OK", "Remove Anyway").
- Checks: `scripts/mac-gate.sh build-test` (app build + GIMKit and GIMUI
  package tests) and `scripts/mac-gate.sh e2e --hub-url ...` on the Mac host
  `a@100.99.1.8`, serialized by `~/gim-ci/.lock-xcode`; station has no Swift
  toolchain.

## Proposal

Six steps as on Android, each landing as a reviewed merge with green gates.
Only the words a user reads change; code, identifiers, string keys, logs,
test identifiers and the SDK keep the old terms (hub, handle, user ID).

### 1. Plain words (glossary) and English copy rewrite

- `docs/glossary.md`: the C1 glossary and writing rules, verbatim.
- Localization foundation: String Catalogs in the GIMUI package
  (`defaultLocalization: "en"`, `resources`), one table per area
  (`Common`, `Chat`, `Onboarding`, `Settings`, `Explainer`, ...) so parallel
  workstreams never edit the same catalog file; every user-visible string goes
  through `String(localized:table:bundle:)` (or SwiftUI's `LocalizedStringKey`
  with the table). GIMFeatures' user-facing text (error presenter, user
  labels, relative dates) is localized without breaking the Foundation-only
  Linux build (swift-foundation provides `String(localized:)`; if a construct
  does not build on Linux, GIMFeatures returns a typed value that GIMUI
  localizes).
- App target: `CFBundleLocalizations` en, zh-Hans, zh-Hant, es and
  `CFBundleDevelopmentRegion` en in `project.yml`, so iOS offers the
  per-app language in the Settings app. Translations themselves are step 4.
- Rewrite all copy on the existing screens outside onboarding and settings
  (chat list, chat, composer, contacts, group info, hubs, devices, link
  flows, common views, notification texts, error presenter) at a
  12-year-old reading level with the glossary terms; errors say what happened
  and what to try. `Info.plist` usage descriptions follow the same rules.
- The "How gim works" explainer strings (C4) land as the `Explainer` table
  with the Android words verbatim, ready for steps 2 and 3.

### 2. Onboarding and account explanation

- Welcome: three short intro pages (no phone number or email, your account
  lives on your devices, messages are locked), then "Create account", "I have
  an account" (link) and "Restore".
- Create account: name first; the server step is skipped when a default
  server exists (`GIMDefaultServerURL`), "Use another server" under a small
  link.
- Recovery kit (C2) instead of the bare code: Account ID and recovery key
  together, explained as a spare key. Actions: copy, share as a text file
  (`ShareLink`, which also reaches password managers through their share
  extensions; iOS has no public save-to-password-manager API). Then the
  check: type the last 4 characters of the key before continuing.
  `RecoveryKit` in GIMFeatures: same text format and label-independent parser
  as Android, with tests that parse Android-written kits and kits copied by
  hand in each language.
- Restore: one paste field that accepts the kit text (Account ID and key
  parsed out), separate fields as fallback.
- Username step explains what it is for ("friends can find you with it").
- UI tests (`E2ETestCase.swift` onboarding helpers, `IdentitySmokeTests`)
  follow the new screens.

### 3. Settings

Entry: the avatar in the chat list top bar (replaces the gear);
`SettingsSheet` goes away. Sections (C4):

- **Profile**: name (edit), username (claim, change, remove), Account ID
  with copy, "My QR code" that friends scan to start a chat (payload: the
  Account ID as plain text; the scanner accepts any text containing a valid
  Account ID token).
- **Account and devices**: what the recovery key is and why to keep it,
  linked devices (today's Devices screen), link a new device.
- **Notifications**: opens the app's system notification settings
  (`UIApplication.openNotificationSettingsURLString`).
- **Appearance**: theme (system, light, dark), applied with
  `preferredColorScheme`; chat colors have a dark set.
- **Language**: opens the per-app language page of the Settings app
  (`UIApplication.openSettingsURLString`), with a line explaining it.
- **Advanced**: servers (today's Hubs screen).
- **Help and about**: "How gim works" (explainer), app and core version,
  open-source licences.
- **Sign out**, separated, confirm dialog that says the recovery kit is
  needed to come back.

New chat gains "Scan QR code" next to the username search. Step 6 entries
have their place but stay hidden until the API exists.

### 4. Languages

- Every remaining literal moves into the catalogs; a package test fails when
  a key lacks one of en, zh-Hans, zh-Hant, es (or a stale/untranslated entry
  remains).
- Ship en, zh-Hans (zh-CN), zh-Hant (zh-TW) and es (C3); plurals and
  date/time formats follow the locale (`Text(date, format:)`,
  `String(localized:)` with plural variants).
- Manual pass on the simulator in each language, screenshots attached to the
  merge.

### 5. UI polish against Signal and Telegram

- Chat list: larger avatars with initials and stable colors, relative times,
  unread badges, message status ticks, clear empty state with "Start a chat".
- Chat: bubble spacing and grouping by sender and time, date chips, reply and
  reaction affordances discoverable by long-press, a composer whose
  attachment and send buttons stay put.
- Accessibility: 44 pt touch targets, labels and hints, Dynamic Type up to
  the accessibility sizes without clipping, VoiceOver order on new screens.
- Consistent navigation bars, dialogs and banners.

### 6. Account safety features (waits on the SDK)

Vendor a gim-client-sdk build with the APIs (xcframework from its CI or a Mac
build, `scripts/sync-gim-core.sh`), extend the mirror and `FakeGimClient`,
then: own profile photo; privacy switches (read receipts, typing) and blocked
users; mute, pin, archive, block, report on chats; "Create a new recovery
key" (new kit replaces the old); delete account. Until then nothing fake.

### Verification

- GIMKit tests for every new view model and parser (recovery kit, settings,
  profile edit, theme, language), written first; GIMUI package tests for
  catalog completeness.
- Each L3 passes `scripts/mac-gate.sh build-test`; each workstream merge
  passes `build-test` and `scripts/mac-gate.sh e2e` against
  `scripts/e2e-hub.sh start` before it lands on main.
- Device E2E stays green; the onboarding smoke tests cover the new flow.

### Workstreams (BKD campaign `l1-0xhhlawj-20261023095300`)

| id | workstream | steps | write scope | after |
|---|---|---|---|---|
| W1 | Copy and localization foundation | 1 | `docs/glossary.md`, `project.yml`, GIMUI `Package.swift` + `Resources/`, GIMUI screens except `Onboarding/`, `Identity/RestoreScreen.swift`, `App/SettingsSheet.swift`; GIMFeatures `Common/`; UI tests matching changed labels | - |
| W2 | Onboarding and recovery kit | 2 | GIMUI `Onboarding/`, `Identity/RestoreScreen.swift`, `Onboarding.xcstrings`; GIMFeatures `Onboarding/`, `Identity/RestoreViewModel.swift`, new `RecoveryKit`; `GIM/UITests` onboarding helpers | W1 |
| W3 | Settings | 3 | new GIMUI `Settings/` and GIMFeatures `Settings/`, `Settings.xcstrings`; `App/SettingsSheet.swift` (removed), `App/RootView.swift`, chat list top bar entry; `Contacts/NewChatScreen.swift` scan entry; `GIM/UITests` settings helpers | W1 |
| W4 | Polish | 5 | GIMUI `ChatList/` rows and empty state, `Timeline/`, `Composer/`, `Common/`, `Chat.xcstrings`/`Common.xcstrings`; GIMFeatures `ChatList/`, `Timeline/`, `Composer/` | W1 |
| W5 | Languages | 4 | every `.xcstrings`, catalog completeness test, locale formatting fixes | W2, W3, W4 |
| W6 | Account safety | 6 | `Vendor/GIMCore`, `GIM_CORE_VERSION`, mirror + fake, Settings entries, chat actions | W3 and the SDK build (C7) |

Merge order: W1, then W2/W3/W4 as each completes (rebased on main), then W5,
then W6.

## Risks

- Large diff across GIMUI; the per-table catalogs and the staged merge order
  keep the workstreams' write scopes apart; W3 and W4 both touch
  `ChatListScreen.swift` (top bar vs rows), resolved at merge.
- `String(localized:)` in the Foundation-only GIMKit on Linux: verified by
  the W1 foundation subtask on both toolchains; fallback is typed values
  localized in GIMUI.
- Visible-label changes break UI tests that match text; each workstream
  updates the tests in its scope and the merge gate runs the device E2E.
- Translations need native review before release.
- The Mac host is shared with gim-mac; gates wait on the lock.
- Step 6 depends on the SDK schedule; its entries stay hidden until then.

## Scope

In: steps 1 to 6 in gim-ios, the workstreams above.

Out: the SDK, gim-core and gim-hub work (SDK plan), gim-mac, any `git push`
(not approved yet), the QR payload contract across clients (reported to the
workspace coordinator as a cross-repo need; iOS encodes the plain Account ID).

## Alternatives

- One String Catalog for the whole app: simpler, but every workstream would
  edit the same JSON file in parallel.
- In-app language override by writing `AppleLanguages` and relaunching:
  avoids leaving the app, but fights the system setting; the per-app
  language page is the platform convention.

## Annotations

- 2026-10-23 user (via workspace coordinator): auto mode; no `git push` until
  decision j5sgwgsd is answered.
