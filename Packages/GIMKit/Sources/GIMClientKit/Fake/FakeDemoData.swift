import Foundation

extension FakeGimClient {
    public static let demoSelfId: UserId = "user-alex"
    public static let demoDirectChatId: ChatId = "chat-sofia"
    public static let demoGroupChatId: ChatId = "chat-crew"
    public static let demoDirectMessageCount = 150

    /// A signed-in client seeded with 3 peers, a direct chat with `demoDirectMessageCount` messages (images, a file,
    /// a reply, reactions, an edited and a deleted message) and a group chat. Demo media files are generated under
    /// `dataDirectory`.
    public static func demo(
        scheduler: any FakeScheduler = RealDelayFakeScheduler(),
        dataDirectory: String = FakeGimClient.defaultDataDirectory,
        now: @escaping @Sendable () -> Date = { Date() },
        autoReply: Bool = true
    ) -> FakeGimClient {
        FakeGimClient(
            scheduler: scheduler, dataDirectory: dataDirectory, now: now, autoReply: autoReply,
            seed: FakeDemoData.seed(dataDirectory: dataDirectory, now: now()))
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

    static func seed(dataDirectory: String, now: Date) -> FakeGimClient.Seed {
        let me = UserProfile(userId: FakeGimClient.demoSelfId, handle: "alex", displayName: "Alex Morgan")
        let sofia = UserProfile(userId: "user-sofia", handle: "sofia", displayName: "Sofia Marin")
        let luca = UserProfile(userId: "user-luca", handle: "luca", displayName: "Luca Bianchi")
        let nikos = UserProfile(userId: "user-nikos", handle: "nikos", displayName: "Nikos Papadopoulos")
        let session = Session(
            userId: me.userId, deviceId: "device-1", handle: me.handle, displayName: me.displayName,
            serverUrl: "https://demo.gim.invalid")

        let mediaDirectory = URL(fileURLWithPath: dataDirectory).appendingPathComponent("demo-media")
        try? FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        let imagePath = mediaDirectory.appendingPathComponent("harbour.png").path
        let imageData = DemoImage.png(width: 160, height: 120)
        try? imageData.write(to: URL(fileURLWithPath: imagePath))
        let filePath = mediaDirectory.appendingPathComponent("crew-list.txt").path
        let fileData = Data("Crew list\nAlex Morgan - skipper\nSofia Marin - navigator\nLuca Bianchi - cook\n".utf8)
        try? fileData.write(to: URL(fileURLWithPath: filePath))
        let image = MediaInfo(
            mediaId: "media-harbour", mime: "image/png", size: UInt64(imageData.count), fileName: "harbour.png",
            width: 160, height: 120, thumbnailPath: imagePath)
        let file = MediaInfo(
            mediaId: "media-crew-list", mime: "text/plain", size: UInt64(fileData.count), fileName: "crew-list.txt")

        var direct = FakeGimClient.StoredChat(
            id: FakeGimClient.demoDirectChatId, kind: .direct, name: "",
            createdAt: now.addingTimeInterval(-30 * 86_400), members: [me.userId, sofia.userId])
        let count = FakeGimClient.demoDirectMessageCount
        for index in 0..<count {
            let isOwn = index % 3 == 0 && index < count - 2
            let sender = isOwn ? me : sofia
            var content = MessageContent.text(lines[index % lines.count])
            switch index {
            case 60, 140: content = .image(image, caption: index == 140 ? "Sunset over the harbour" : nil)
            case 141: content = .file(file, caption: "Updated crew list")
            default: break
            }
            let message = TimelineMessage(
                id: String(format: "msg-sofia-%03d", index), chatId: direct.id, senderId: sender.userId,
                senderName: sender.displayName, isOwn: isOwn,
                timestamp: now.addingTimeInterval(-Double(count - index) * 41 * 60), content: content,
                sendState: isOwn ? .read : nil)
            direct.messages.append(FakeGimClient.StoredMessage(message: message))
        }
        direct.messages[143].message.replyTo = ReplyPreview(
            messageId: direct.messages[141].message.id, senderName: me.displayName, preview: "crew-list.txt")
        direct.messages[143].message.content = .text("Thanks, I'll print it for the harbour office.")
        FakeGimClient.setReaction(
            &direct.messages[144], emoji: "👍", user: sofia.userId, active: true, selfId: me.userId)
        FakeGimClient.setReaction(&direct.messages[144], emoji: "❤️", user: me.userId, active: true, selfId: me.userId)
        FakeGimClient.setReaction(
            &direct.messages[144], emoji: "❤️", user: sofia.userId, active: true, selfId: me.userId)
        direct.messages[147].message.content = .text("Departure moved to 09:30, the fuel dock opens late.")
        direct.messages[147].message.editedAt = direct.messages[147].message.timestamp.addingTimeInterval(120)
        direct.messages[146].message.content = .deleted
        direct.messages[146].message.sendState = nil
        direct.loadedCount = min(FakeGimClient.initialWindow, count)
        direct.unreadCount = 2

        var group = FakeGimClient.StoredChat(
            id: FakeGimClient.demoGroupChatId, kind: .group, name: "Aegean Crew",
            createdAt: now.addingTimeInterval(-7 * 86_400),
            members: [me.userId, sofia.userId, luca.userId, nikos.userId])
        let groupLines: [(UserProfile, String)] = [
            (luca, "Provisioning list is in the shared folder."),
            (nikos, "I can bring the spare dinghy pump."),
            (me, "Great, thanks Nikos."),
            (sofia, "Weather window looks good for Saturday."),
            (luca, "Who's on dinner duty tonight?"),
            (nikos, "Me, grilled octopus 🐙"),
        ]
        for (index, entry) in groupLines.enumerated() {
            let (sender, text) = entry
            let message = TimelineMessage(
                id: "msg-crew-\(index)", chatId: group.id, senderId: sender.userId, senderName: sender.displayName,
                isOwn: sender == me, timestamp: now.addingTimeInterval(-Double(groupLines.count - index) * 600 - 60),
                content: .text(text), sendState: sender == me ? .read : nil)
            group.messages.append(FakeGimClient.StoredMessage(message: message))
        }
        group.loadedCount = group.messages.count
        group.unreadCount = 3

        return FakeGimClient.Seed(
            session: session, users: [me, sofia, luca, nikos], chats: [direct, group],
            media: [image.mediaId: imagePath, file.mediaId: filePath])
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
