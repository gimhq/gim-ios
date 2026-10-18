import GIMClientKit

/// Delivery status of an own message, as shown by the status ticks.
public enum MessageStatus: Sendable, Hashable {
    case sending
    case sent
    case delivered
    case read
    case failed(reason: String, cause: SendFailure)

    public init(_ state: SendState) {
        switch state {
        case .pending: self = .sending
        case .sent: self = .sent
        case .delivered: self = .delivered
        case .read: self = .read
        case .failed(let reason, let cause): self = .failed(reason: reason, cause: cause)
        }
    }
}

/// What a message bubble shows.
public enum MessageBody: Sendable, Hashable {
    case text(String)
    case image(media: MediaRef, width: UInt32?, height: UInt32?, caption: String?)
    case file(media: MediaRef, fileName: String, sizeText: String, caption: String?)
    /// Deleted or unsupported content, shown as secondary italic text.
    case placeholder(String)
}

/// A message prepared for display.
public struct TimelineMessageRow: Sendable, Hashable {
    public var message: MessageItem
    public var body: MessageBody
    /// Shown above the first message of a run, in groups only, never for own messages.
    public var senderName: String?
    public var isFirstInRun: Bool
    /// Last message of a run: the bubble gets a tail and the run ends with a larger gap.
    public var hasTail: Bool
    public var reply: ReplyPreview?
    public var reactions: [ReactionGroup]
    public var isEdited: Bool
    public var timeText: String
    /// Own messages only.
    public var status: MessageStatus?
    /// The attachment couldn't be downloaded for now (the uploader's server is unreachable or refusing): the cell
    /// offers a retry instead of the media.
    public var isMediaUnavailable: Bool

    public init(
        message: MessageItem, body: MessageBody, senderName: String?, isFirstInRun: Bool, hasTail: Bool,
        reply: ReplyPreview?, reactions: [ReactionGroup], isEdited: Bool, timeText: String, status: MessageStatus?,
        isMediaUnavailable: Bool = false
    ) {
        self.message = message
        self.body = body
        self.senderName = senderName
        self.isFirstInRun = isFirstInRun
        self.hasTail = hasTail
        self.reply = reply
        self.reactions = reactions
        self.isEdited = isEdited
        self.timeText = timeText
        self.status = status
        self.isMediaUnavailable = isMediaUnavailable
    }

    public var isOwn: Bool { message.isOwn }
}

/// One row of the timeline view, with an id that stays stable across updates.
public struct TimelineDisplayItem: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable, Hashable {
        case message(TimelineMessageRow)
        case dateSeparator(String)
        case membership(String)
        case typing(String)
    }

    public var id: String
    public var kind: Kind

    public init(id: String, kind: Kind) {
        self.id = id
        self.kind = kind
    }

    /// Id of the row showing message `messageId`.
    public static func id(forMessage messageId: String) -> String {
        "msg:\(messageId)"
    }

    public static let typingId = "typing"

    public var messageRow: TimelineMessageRow? {
        if case .message(let row) = kind { row } else { nil }
    }

    /// Changes whenever anything that affects the row's layout or rendering changes; stable within one process.
    public var contentRevision: Int { kind.hashValue }
}

/// Changes between two lists of display items, by id. `deletedIds` and `reloadedIds` refer to the old list,
/// `insertedIds` to the new one. A reset (new subscription or out-of-sync diffs) carries no ids and needs a full
/// reload.
public struct TimelineChangeSet: Sendable, Hashable {
    public var isReset: Bool
    /// Every inserted row sits above the first message that was already shown: older history was loaded and the
    /// view should keep its visual anchor.
    public var isPrepend: Bool
    public var insertedIds: [String]
    public var deletedIds: [String]
    public var reloadedIds: [String]

    public init(
        isReset: Bool = false, isPrepend: Bool = false, insertedIds: [String] = [], deletedIds: [String] = [],
        reloadedIds: [String] = []
    ) {
        self.isReset = isReset
        self.isPrepend = isPrepend
        self.insertedIds = insertedIds
        self.deletedIds = deletedIds
        self.reloadedIds = reloadedIds
    }

    public static let reset = TimelineChangeSet(isReset: true)

    public var isEmpty: Bool {
        !isReset && insertedIds.isEmpty && deletedIds.isEmpty && reloadedIds.isEmpty
    }

    /// The changes that turn `old` into `new`. With `isReset` the result is `.reset`.
    public init(from old: [TimelineDisplayItem], to new: [TimelineDisplayItem], isReset: Bool = false) {
        if isReset {
            self = .reset
            return
        }
        let oldById = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let newIds = Set(new.map(\.id))
        let inserted = new.enumerated().filter { oldById[$0.element.id] == nil }
        let reloaded = new.filter { item in oldById[item.id].map { $0 != item } ?? false }
        // Day separators of the old first day move up with older history, so only messages count as anchors.
        let anchorIndex = old.first { $0.messageRow != nil && newIds.contains($0.id) }
            .flatMap { anchor in new.firstIndex { $0.id == anchor.id } }
        let isPrepend =
            !inserted.isEmpty
            && anchorIndex.map { anchor in inserted.allSatisfy { $0.offset < anchor } }
                ?? false
        self.init(
            isPrepend: isPrepend,
            insertedIds: inserted.map(\.element.id),
            deletedIds: old.map(\.id).filter { !newIds.contains($0) },
            reloadedIds: reloaded.map(\.id))
    }
}
