import Foundation

extension FakeGimClient {
    public static let demoSelfId = "user-alex"
    public static let demoDirectChatId = "chat-sofia"
    public static let demoGroupChatId = "chat-crew"
    public static let demoDirectMessageCount = 150

    /// A client seeded with 3 peers, a direct chat with `demoDirectMessageCount` messages over several days (images,
    /// a file, a reply, reactions, an edited and a deleted message) and a group chat. Demo media files are generated
    /// under `dataDirectory`. Sync is stopped until `startSync()`.
    ///
    /// - Parameter registered: signed in as Alex Morgan (`demoSelfId`). When `false`, the client starts without a
    ///   session and seeds the chats around whoever calls `createIdentity` (or links as the demo user).
    public static func demo(
        scheduler: any FakeScheduler = RealDelayFakeScheduler(),
        dataDirectory: String = FakeGimClient.defaultDataDirectory,
        now: @escaping @Sendable () -> Date = { Date() },
        autoReply: Bool = true,
        registered: Bool = true,
        networkReachable: Bool = true,
        homeHubUrl: String = FakeGimClient.defaultHomeHubUrl
    ) -> FakeGimClient {
        let options = Options(
            scheduler: scheduler, dataDirectory: dataDirectory, now: now, autoReply: autoReply,
            networkReachable: networkReachable, homeHubUrl: homeHubUrl)
        guard registered else {
            return FakeGimClient(
                options: options, seed: Seed(users: FakeDemoData.peers), seedsDemoOnRegister: true)
        }
        let me = FakeDemoData.me
        var seed = FakeDemoData.seed(me: me, dataDirectory: dataDirectory, now: now())
        seed.session = Session(userId: me.userId, deviceId: "device-1", handle: me.handle, displayName: me.displayName)
        return FakeGimClient(options: options, seed: seed, seedsDemoOnRegister: false)
    }
}

enum FakeDemoData {
    static let replies = [
        "Sounds good!",
        "Let me check the forecast and get back to you.",
        "Perfect, see you at the marina.",
        "Haha, true 😄",
        "Can you send me the exact location?",
    ]

    /// The demo user (`FakeGimClient.demoSelfId`).
    static let me = UserProfile(userId: FakeGimClient.demoSelfId, handle: "alex", displayName: "Alex Morgan")

    static let peers = [
        UserProfile(userId: "user-sofia", handle: "sofia", displayName: "Sofia Marin"),
        UserProfile(userId: "user-luca", handle: "luca", displayName: "Luca Bianchi"),
        UserProfile(userId: "user-nikos", handle: "nikos", displayName: "Nikos Papadopoulos"),
    ]

    private static let lines = [
        "Morning! Are we still leaving Piraeus at nine?",
        "Yes, the forecast says Meltemi drops to 4 Bft by noon.",
        "I'll pick up fresh bread on the way.",
        "Do we have enough water for two days?",
        "Topped up both tanks yesterday.",
        "Hydra or Poros for tonight?",
        "Poros, the quay in Hydra is always full in August.",
        "Good call. I'll radio the harbour master.",
        "Did you check the anchor windlass?",
        "Fixed it, it was the fuse again.",
        "Swim stop at Moni island?",
        "Absolutely, the water there is unreal.",
    ]

    /// Chats and media around `me`; `session` is left unset.
    static func seed(me: UserProfile, dataDirectory: String, now: Date) -> FakeGimClient.Seed {
        let (sofia, luca, nikos) = (peers[0], peers[1], peers[2])
        let nowMs = FakeGimClient.milliseconds(now)
        let minute: UInt64 = 60_000

        let mediaDirectory = URL(fileURLWithPath: dataDirectory).appendingPathComponent("demo-media")
        try? FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        let imagePath = mediaDirectory.appendingPathComponent("harbour.png").path
        let imageData = DemoImage.png(width: 160, height: 120)
        try? imageData.write(to: URL(fileURLWithPath: imagePath))
        let filePath = mediaDirectory.appendingPathComponent("crew-list.txt").path
        let fileData = Data("Crew list\nAlex Morgan - skipper\nSofia Marin - navigator\nLuca Bianchi - cook\n".utf8)
        try? fileData.write(to: URL(fileURLWithPath: filePath))

        var media: [String: FakeGimClient.StoredMedia] = [:]
        var direct = FakeGimClient.StoredChat(
            id: FakeGimClient.demoDirectChatId, kind: .direct, name: "", createdAtMs: nowMs - 30 * 1_440 * minute,
            members: [me.userId, sofia.userId])
        let count = FakeGimClient.demoDirectMessageCount
        for index in 0..<count {
            let isOwn = index % 3 == 0 && index < count - 2
            let messageId = String(format: "msg-sofia-%03d", index)
            func ref(mime: String, size: Int, thumbnail: Bool) -> MediaRef {
                MediaRef(
                    chatId: direct.id, messageId: messageId, mime: mime, size: UInt64(size), hasThumbnail: thumbnail)
            }
            var content = MessageContent.text(body: lines[index % lines.count])
            switch index {
            case 60, 140:
                content = .image(
                    media: ref(mime: "image/png", size: imageData.count, thumbnail: true), width: 160, height: 120,
                    caption: index == 140 ? "Sunset over the harbour" : nil)
                media[FakeGimClient.mediaKey(chatId: direct.id, messageId: messageId)] = FakeGimClient.StoredMedia(
                    path: imagePath, thumbnailPath: imagePath)
            case 141:
                content = .file(
                    media: ref(mime: "text/plain", size: fileData.count, thumbnail: false),
                    fileName: "crew-list.txt", caption: "Updated crew list")
                media[FakeGimClient.mediaKey(chatId: direct.id, messageId: messageId)] = FakeGimClient.StoredMedia(
                    path: filePath, thumbnailPath: nil)
            default:
                break
            }
            let item = MessageItem(
                messageId: messageId, chatId: direct.id, sender: isOwn ? me : sofia, isOwn: isOwn,
                sentAtMs: nowMs - UInt64(count - index) * 41 * minute, content: content, replyTo: nil, reactions: [],
                edited: false, sendState: isOwn ? .read : nil)
            direct.entries.append(.message(FakeGimClient.StoredMessage(item: item)))
        }
        mutateMessage(&direct, 143) {
            $0.item.replyTo = ReplyPreview(
                messageId: "msg-sofia-141", senderName: me.displayName, text: "File: crew-list.txt")
            $0.item.content = .text(body: "Thanks, I'll print it for the harbour office.")
        }
        mutateMessage(&direct, 144) {
            FakeGimClient.setReaction(&$0, emoji: "👍", user: sofia.userId, active: true, selfId: me.userId)
            FakeGimClient.setReaction(&$0, emoji: "❤️", user: me.userId, active: true, selfId: me.userId)
            FakeGimClient.setReaction(&$0, emoji: "❤️", user: sofia.userId, active: true, selfId: me.userId)
        }
        mutateMessage(&direct, 146) {
            $0.item.content = .deleted
            $0.item.sendState = nil
        }
        mutateMessage(&direct, 147) {
            $0.item.content = .text(body: "Departure moved to 09:30, the fuel dock opens late.")
            $0.item.edited = true
        }
        direct.loadedCount = min(FakeGimClient.initialWindow, count)
        direct.unreadCount = 2

        var group = FakeGimClient.StoredChat(
            id: FakeGimClient.demoGroupChatId, kind: .group, name: "Aegean Crew",
            createdAtMs: nowMs - 7 * 1_440 * minute, members: [me.userId, sofia.userId, luca.userId, nikos.userId])
        let groupLines: [(UserProfile, String)] = [
            (luca, "Provisioning list is in the shared folder."),
            (nikos, "I can bring the spare dinghy pump."),
            (me, "Great, thanks Nikos."),
            (sofia, "Weather window looks good for Saturday."),
            (luca, "Who's on dinner duty tonight?"),
            (nikos, "Me, grilled octopus 🐙"),
        ]
        for (index, entry) in groupLines.enumerated() {
            let (sender, body) = entry
            let item = MessageItem(
                messageId: "msg-crew-\(index)", chatId: group.id, sender: sender, isOwn: sender == me,
                sentAtMs: nowMs - UInt64(groupLines.count - index) * 10 * minute - minute,
                content: .text(body: body), replyTo: nil, reactions: [], edited: false,
                sendState: sender == me ? .read : nil)
            group.entries.append(.message(FakeGimClient.StoredMessage(item: item)))
        }
        group.loadedCount = group.entries.count
        group.unreadCount = 3

        return FakeGimClient.Seed(users: [me] + peers, chats: [direct, group], media: media)
    }

    private static func mutateMessage(
        _ chat: inout FakeGimClient.StoredChat, _ index: Int, _ mutate: (inout FakeGimClient.StoredMessage) -> Void
    ) {
        guard var stored = chat.entries[index].message else { return }
        mutate(&stored)
        chat.entries[index] = .message(stored)
    }
}

/// Minimal PNG encoder (stored deflate blocks) so demo images need no image framework.
enum DemoImage {
    static func png(width: Int, height: Int) -> Data {
        var raw = [UInt8]()
        raw.reserveCapacity((width * 3 + 1) * height)
        for y in 0..<height {
            raw.append(0)
            for x in 0..<width {
                let sky = y < height * 2 / 3
                raw.append(sky ? UInt8(255 - y) : 20)
                raw.append(sky ? UInt8(120 + x / 4) : UInt8(80 + x / 4))
                raw.append(sky ? 90 : UInt8(140 + y / 2))
            }
        }
        var header = [UInt8]()
        header += bigEndian(UInt32(width)) + bigEndian(UInt32(height))
        header += [8, 2, 0, 0, 0]
        var data = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        data += chunk("IHDR", header)
        data += chunk("IDAT", zlibStored(raw))
        data += chunk("IEND", [])
        return data
    }

    private static func zlibStored(_ bytes: [UInt8]) -> [UInt8] {
        var out: [UInt8] = [0x78, 0x01]
        var offset = 0
        repeat {
            let length = min(65_535, bytes.count - offset)
            let isLast = offset + length == bytes.count
            out.append(isLast ? 1 : 0)
            out += [UInt8(length & 0xFF), UInt8(length >> 8), UInt8(~length & 0xFF), UInt8((~length >> 8) & 0xFF)]
            out += bytes[offset..<(offset + length)]
            offset += length
        } while offset < bytes.count
        var a: UInt32 = 1
        var b: UInt32 = 0
        for byte in bytes {
            a = (a + UInt32(byte)) % 65_521
            b = (b + a) % 65_521
        }
        return out + bigEndian(b << 16 | a)
    }

    private static func chunk(_ type: String, _ payload: [UInt8]) -> [UInt8] {
        let body = Array(type.utf8) + payload
        return bigEndian(UInt32(payload.count)) + body + bigEndian(crc32(body))
    }

    private static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1
            }
        }
        return ~crc
    }

    private static func bigEndian(_ value: UInt32) -> [UInt8] {
        [UInt8(value >> 24), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }
}
