import Foundation
import GIMClientKit

/// What the Notification Service Extension shows for a push.
public struct NotificationPresentation: Sendable, Hashable {
    /// `false` (`NotificationContent.shouldDisplay`): the extension delivers empty content, so nothing is shown.
    public var isDisplayed: Bool
    /// Empty when the chat is unknown; the system then shows the app name.
    public var title: String
    public var body: String
    /// The chat id, grouping the notifications of a chat; empty when the chat is unknown.
    public var threadIdentifier: String
    /// Stored as `userInfo["collapseId"]`; delivered notifications with the same id are removed first.
    public var collapseId: String?
    public var kind: NotificationKind

    /// Shown when the push can't be processed or in time: like gim-core's generic content.
    public static let generic = NotificationPresentation(
        isDisplayed: true, title: "", body: "New message", threadIdentifier: "", collapseId: nil, kind: .generic)

    public init(
        isDisplayed: Bool, title: String, body: String, threadIdentifier: String, collapseId: String?,
        kind: NotificationKind
    ) {
        self.isDisplayed = isDisplayed
        self.title = title
        self.body = body
        self.threadIdentifier = threadIdentifier
        self.collapseId = collapseId
        self.kind = kind
    }

    /// The same mapping for every kind: the title is the chat title, or "<sender> in <chat>" when the sender's name
    /// differs from the chat title (a group; in a direct chat the title is the other user's name); without a chat
    /// title the sender's name. The body is gim-core's (`reacted 👍`, `Photo`, `New message`, …).
    public init(_ content: NotificationContent) {
        let title: String
        switch (content.chatTitle, content.senderDisplayName) {
        case (let chat?, let sender?) where sender != chat: title = "\(sender) in \(chat)"
        case (let chat?, _): title = chat
        case (nil, let sender?): title = sender
        case (nil, nil): title = ""
        }
        self.init(
            isDisplayed: content.shouldDisplay, title: title, body: content.body,
            threadIdentifier: content.chatId ?? "", collapseId: content.collapseId, kind: content.kind)
    }
}

/// The Notification Service Extension's work for one push: creates an extension-mode client on the shared data
/// directory, lets gim-core process the payload and maps the result. The client is released when it returns.
public struct PushNotificationHandler: Sendable {
    /// The userInfo key of the hub's push payload (gim-hub docs/push-mock.md section 3: the webhook body's `payload`).
    public static let payloadKey = "gim"
    /// The userInfo key the extension stores `NotificationPresentation.collapseId` under.
    public static let collapseIdKey = "collapseId"

    private let factory: any GimClientFactory
    private let makeHooks: @Sendable () throws -> any PlatformHooks
    private let serverUrl: String?
    private let onFailure: @Sendable (String) -> Void

    /// - Parameters:
    ///   - makeHooks: the platform hooks on the App Group container, made per push.
    ///   - serverUrl: the app's last used server; `nil` before the first sign-in.
    ///   - onFailure: why the content is generic, e.g. for the system log.
    public init(
        factory: any GimClientFactory, makeHooks: @escaping @Sendable () throws -> any PlatformHooks,
        serverUrl: String?, onFailure: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.factory = factory
        self.makeHooks = makeHooks
        self.serverUrl = serverUrl
        self.onFailure = onFailure
    }

    /// The payload under `payloadKey` as JSON text (a JSON object, as `simctl push` delivers it, or a string).
    public static func payload(from userInfo: [AnyHashable: Any]) -> String? {
        guard let value = userInfo[payloadKey] else { return nil }
        if let text = value as? String { return text }
        guard JSONSerialization.isValidJSONObject(value),
            let data = try? JSONSerialization.data(withJSONObject: value)
        else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// `NotificationPresentation.generic` when there is no payload or server, or when creating the client (e.g. a
    /// missing database key, or `Storage` after a store lock timeout) or processing the push fails.
    public func presentation(payload: String?) async -> NotificationPresentation {
        guard let payload else {
            onFailure("no \(Self.payloadKey) payload")
            return .generic
        }
        guard let serverUrl else {
            onFailure("no server URL in the shared defaults")
            return .generic
        }
        do {
            let client = try await factory.make(
                config: ClientConfig(serverUrl: serverUrl, mode: .extension), hooks: makeHooks())
            return NotificationPresentation(try await client.processPush(payload: payload))
        } catch {
            onFailure("\(error)")
            return .generic
        }
    }
}
