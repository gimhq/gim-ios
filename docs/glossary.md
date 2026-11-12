# Glossary

The words the app shows to people, and the older terms they replace. Use the
user-facing word in every piece of text a user reads, the same way on every
screen.

| Old term (code, logs, SDK) | User-facing word | What it means |
|---|---|---|
| Hub | Server | The computer that passes your messages on. It can't read them. |
| Handle | — | Not shown: usernames were removed. People find each other by Account ID only. |
| User ID | Account ID | A long code that is your account's real address, and the only way to find someone. |
| Recovery code | Recovery key | A spare key that brings your account back on a new phone. |
| Revoke device | Remove device | Sign a phone or tablet out of your account. |
| Verified hub | Connected | The app reached this server and it answered. |
| Unverified hub | Not checked | The app has not reached this server yet. |
| Home hub / Primary hub | Main server | The server your account lives on. |

Plurals follow the same mapping (hubs → servers).

## Account safety and chat actions

These words name the chat actions and the account safety settings. The code names already match them (`blockUser`,
`setChatMuted`, `setChatPinned`, `setChatArchived`, `setAvatar`, `setReadReceipts`, `setTypingIndicators`,
`rotateRecoveryCode`, `deleteAccount`, ...), so there is no old term to map.

| User-facing word | What it means |
|---|---|
| Keep server | The server that backs up your privacy settings and receives the reports you send. The backup is encrypted; reports are not, so never say that all your data is encrypted. "Keep" is a name and stays untranslated. On by default; Settings → Keep server changes or turns it off. |
| Pin / Unpin | Keep a chat at the top of the list, or stop keeping it there. |
| Pinned | This chat stays at the top of the list. |
| Mute / Unmute | Stop or restart notifications for a chat. |
| Muted | You don't get notifications for this chat. |
| For 1 hour / For 8 hours / For 1 week / Always | How long a chat stays muted. |
| Archive / Unarchive | Move a chat out of the main list, or bring it back. |
| Archived chats | The chats you moved out of the main list. |
| Block / Unblock | Stop or allow messages from a person. |
| Blocked people | The people you blocked. |
| More | The menu with the rest of a chat's actions. |
| Profile photo | The picture friends see next to your name. |
| Privacy | Settings for what others can see about you. |
| Read receipts | Let others see when you read their messages. |
| Typing indicators | Let others see when you're typing. |
| Create a new recovery key | Replace your recovery key; the old one stops working. |
| Delete account | Remove your account from your servers for good. |
| DELETE | The word you type to confirm that you delete your account. |

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
| Block / Unblock | 屏蔽 / 取消屏蔽 | 封鎖 / 解除封鎖 | Bloquear / Desbloquear |
| Blocked people | 已屏蔽的人 | 已封鎖的人 | Personas bloqueadas |
| Mute / Unmute / Muted | 静音 / 取消静音 / 已静音 | 靜音 / 取消靜音 / 已靜音 | Silenciar / Activar sonido / Silenciado |
| For 1 hour / 8 hours / 1 week / Always (mute) | 1 小时 / 8 小时 / 1 周 / 永久 | 1 小時 / 8 小時 / 1 週 / 永久 | Durante 1 hora / 8 horas / 1 semana / Siempre |
| Pin / Unpin / Pinned | 置顶 / 取消置顶 / 已置顶 | 置頂 / 取消置頂 / 已置頂 | Fijar / Dejar de fijar / Fijado |
| Archive / Unarchive | 归档 / 取消归档 | 封存 / 取消封存 | Archivar / Desarchivar |
| Archived chats | 已归档的聊天 | 已封存的聊天 | Chats archivados |
| More (menu) | 更多 | 更多 | Más |
| Read receipts | 已读回执 | 已讀回條 | Confirmaciones de lectura |
| Typing indicators | 输入状态 | 輸入狀態 | Indicadores de escritura |
| Profile photo | 头像 | 大頭貼照 | foto de perfil |
| Privacy | 隐私 | 隱私權 | Privacidad |
| Create a new recovery key / Create new key | 创建新的恢复密钥 / 创建新密钥 | 建立新的復原金鑰 / 建立新金鑰 | Crear una nueva clave de recuperación / Crear nueva clave |
| Delete account | 删除账号 | 刪除帳號 | Eliminar cuenta |
| Keep server | Keep 服务器 | Keep 伺服器 | servidor Keep |
| DELETE (typed to confirm) | 删除 | 刪除 | ELIMINAR |

New strings get all four languages in the same change; the catalog completeness tests fail otherwise.
