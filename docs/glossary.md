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

## Translations

gim ships in en, zh-Hans (zh-CN), zh-Hant (zh-TW) and es; Chinese addresses the user as 你, zh-Hant follows Taiwan
usage, Spanish uses neutral informal tú, and the product name is never translated.

| English (user-facing) | zh-Hans | zh-Hant | es |
|---|---|---|---|
| Server / servers | 服务器 | 伺服器 | servidor / servidores |
| Main server | 主服务器 | 主要伺服器 | servidor principal |
| Username | 用户名 | 使用者名稱 | nombre de usuario |
| Account ID | 账号 ID | 帳號 ID | ID de cuenta |
| Account | 账号 | 帳號 | cuenta |
| Recovery key | 恢复密钥 | 復原金鑰 | clave de recuperación |
| Recovery kit | 恢复资料 | 復原資料 | kit de recuperación |
| Restore (an account) | 恢复 | 復原 | restaurar |
| Device / Linked devices | 设备 / 已关联的设备 | 裝置 / 已連結的裝置 | dispositivo / Dispositivos vinculados |
| Link a device | 关联设备 | 連結裝置 | vincular un dispositivo |
| Remove (device, server, member) | 移除 | 移除 | quitar |
| Connected (server state) | 已连接 | 已連線 | Conectado |
| Not checked (server state) | 未检查 | 未檢查 | Sin comprobar |
| Chat / Chats | 聊天 | 聊天 | chat / Chats |
| Group | 群组 | 群組 | grupo |
| Message | 消息 | 訊息 | mensaje |
| Contact | 联系人 | 聯絡人 | contacto |
| Member | 成员 | 成員 | miembro |
| Settings | 设置 | 設定 | Ajustes |
| Profile | 个人资料 | 個人資料 | Perfil |
| Appearance | 外观 | 外觀 | Apariencia |
| Language | 语言 | 語言 | Idioma |
| Sign out | 退出登录 | 登出 | Cerrar sesión |
| Try again | 重试 | 重試 | Reintentar |
| Scan / QR code | 扫描 / 二维码 | 掃描 / QR 碼 | escanear / código QR |
| Copy | 复制 | 複製 | Copiar |
| Cancel / Done / OK | 取消 / 完成 / 好 | 取消 / 完成 / 好 | Cancelar / Listo / Aceptar |
| Encrypted (end-to-end) | 端到端加密 | 端對端加密 | cifrado de extremo a extremo |

New strings get all four languages in the same change; the catalog completeness tests fail otherwise.
