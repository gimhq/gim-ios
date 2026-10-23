# Glossary

The words the app shows to people, and the older terms they replace. Use the
user-facing word in every piece of text a user reads, the same way on every
screen.

| Old term (code, logs, SDK) | User-facing word | What it means |
|---|---|---|
| Hub | Server | The computer that passes your messages on. It can't read them. |
| Handle | Username | A name friends can type to find you. |
| User ID | Account ID | A long code that is your account's real address. |
| Recovery code | Recovery key | A spare key that brings your account back on a new phone. |
| Revoke device | Remove device | Sign a phone or tablet out of your account. |
| Verified hub | Connected | The app reached this server and it answered. |
| Unverified hub | Not checked | The app has not reached this server yet. |
| Home hub / Primary hub | Main server | The server your account lives on. |

Plurals follow the same mapping (hubs → servers, handles → usernames).

## Writing rules

Write for a 12-year-old. Signal and Telegram are the benchmark.

- Short sentences, one idea each. Plain everyday words; no protocol jargon
  ("federation", "session", "identity key", "payload", "endpoint").
- Say what to do next when there is a next step.
- Errors say what happened, then what to try: "Couldn't send. Check your
  internet and try again." Never blame the user. No raw error codes.
- Buttons and menu items are short verbs: "Remove", "Try again", "Copy".
- Titles use sentence case: "Linked devices", not "Linked Devices".
- `contentDescription` says what the control does: "Send message", "Go back".
- Keep every format placeholder (`%1$s`, `%2$d`, ...) with the same index,
  type and meaning, and keep plurals quantities.
- All user-visible text lives in string resources. Lint reports
  `HardcodedText` as an error.

## Code keeps the old terms

Only the text a user reads changes. Code, identifiers, string resource keys,
logs, test tags and the gim-client-sdk keep the old terms (hub, handle, user
ID, ...). Support and developers can use the table above to map between what
a user sees and what the code and logs say.

## iOS note

- `accessibilityLabel` and `accessibilityHint` take the place of Android's `contentDescription`: the label says what
  the control does ("Send message", "Go back"), the hint what happens next.
- There is no lint rule; the String Catalog completeness test of the GIMUI package (workstream W5) replaces Android's
  `HardcodedText` check. Every user-visible string goes through a String Catalog table (see README, "Localization").
