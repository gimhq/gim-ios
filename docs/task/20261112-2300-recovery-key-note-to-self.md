# 20261112-2300-recovery-key-note-to-self SDK without handles, recovery key in Settings, note to self

- **status**: completed
- **priority**: P1
- **owner**: bkd-l2/gim-ios
- **createdAt**: 2026-11-12 23:00

## Description

Phase B of campaign `l1-0xhhlawj-20261112-1924` (L1 issue `0xhhlawj`): vendor gim-client-sdk `2e2e5d4` and remove
every handle API and field; Settings → Recovery key shows the key kept on this device after device authentication,
protected from screenshots and screen capture, with "Create a new recovery key" on a device without it; the note to
self is listed first with the own avatar and a note badge and opens from New chat and Settings.

## ActiveForm

Adding the recovery key screen and the note to self

## Dependencies

- **blocked by**: gim-client-sdk `2e2e5d4` (K3)
- **blocks**: gim-mac phase B (reuses the GIMKit API)

## Notes

- GIMKit API for gim-mac: `GimClientAPI.recoveryCode() throws -> String?`, `ChatSummary.isNoteToSelf`,
  `RecoveryKeyViewModel`, `DeviceAuthenticator`, `DeviceAuthResult`, `RecoveryKeyRotationViewModel.onKitConfirmed`,
  `ChatRow.isNoteToSelf` / `avatarId` / `avatarName` / `noteToSelfTitle`, `ChatActionsViewModel.isNoteToSelf`,
  `NewChatViewModel.startNoteToSelf()`; removed: `claimHandle`, `releaseHandle`, `findUser`, `Session.handle`,
  `UserProfile.handle`.
- UI tests skip device authentication with the Debug launch argument `-GIMSkipDeviceAuth YES` (simulators have no
  passcode); IdentitySmokeTests shows the key and writes to the note to self from the app and a linked device.
