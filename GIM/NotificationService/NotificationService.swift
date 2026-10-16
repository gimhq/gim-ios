import Foundation
import GIMClientKit
import GIMFeatures
import GIMPlatform
import UserNotifications

/// Shows the decrypted content of a push. gim-core processes the hub's payload with an extension-mode client on the
/// App Group's data directory and the server the app last used (`PushNotificationHandler`); the client is released
/// after each push. Appends `nse seq=… footprint_bytes=… elapsed_ms=… kind=…` to `<App Group container>/gim-nse.log`.
final class NotificationService: UNNotificationServiceExtension {
    private var delivery: Delivery?

    override func didReceive(
        _ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        let started = Date()
        let delivery = Delivery(contentHandler)
        self.delivery = delivery
        let payload = PushNotificationHandler.payload(from: request.content.userInfo)
        let handler = PushNotificationHandler(
            factory: RealGimClientFactory(),
            makeHooks: { AppPlatformHooks(dataDirectory: try AppDirectories.dataDirectory.path) },
            serverUrl: AppGroup.defaults.string(forKey: AppGroup.serverUrlKey))
        Task {
            let presentation = await handler.presentation(payload: payload)
            if let collapseId = presentation.collapseId {
                await Self.removeDelivered(collapseId: collapseId)
            }
            delivery.deliver(presentation)
            Self.logMetrics(started: started, kind: presentation.kind)
        }
    }

    /// The best attempt: the generic content.
    override func serviceExtensionTimeWillExpire() {
        delivery?.deliver(.generic)
    }

    /// Every hub of the user may push the same message: drop what is already shown for it.
    private static func removeDelivered(collapseId: String) async {
        let center = UNUserNotificationCenter.current()
        let identifiers = await center.deliveredNotifications()
            .filter { $0.request.content.userInfo[PushNotificationHandler.collapseIdKey] as? String == collapseId }
            .map(\.request.identifier)
        if !identifiers.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: identifiers)
        }
    }

    private static func logMetrics(started: Date, kind: NotificationKind) {
        guard let container = try? AppGroup.containerURL else { return }
        let log = PushMetricsLog(url: container.appendingPathComponent("gim-nse.log"))
        _ = try? log.append(
            footprintBytes: physicalFootprint(), elapsedMs: Int(Date().timeIntervalSince(started) * 1000), kind: kind)
    }

    /// The process's peak `phys_footprint` (the figure the extension's memory limit applies to), or the current one
    /// when the kernel reports no peak; 0 if `task_info` fails.
    private static func physicalFootprint() -> UInt64 {
        // `task_self_trap()` instead of the `mach_task_self_` global, which Swift 6 rejects as shared mutable state.
        let task = task_self_trap()
        defer { mach_port_deallocate(task, task) }
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(task, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return info.ledger_phys_footprint_peak > 0 ? UInt64(info.ledger_phys_footprint_peak) : info.phys_footprint
    }
}

/// Hands content to the system once: the processed push, or the best attempt when time runs out first.
private final class Delivery: @unchecked Sendable {
    private let lock = NSLock()
    private var contentHandler: ((UNNotificationContent) -> Void)?

    init(_ contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
    }

    func deliver(_ presentation: NotificationPresentation) {
        let handler = lock.withLock {
            defer { contentHandler = nil }
            return contentHandler
        }
        handler?(Self.content(for: presentation))
    }

    /// Empty content when the push is not displayed (`NotificationContent.shouldDisplay`).
    private static func content(for presentation: NotificationPresentation) -> UNNotificationContent {
        guard presentation.isDisplayed else { return UNNotificationContent() }
        let content = UNMutableNotificationContent()
        content.title = presentation.title
        content.body = presentation.body
        content.threadIdentifier = presentation.threadIdentifier
        content.sound = .default
        if let collapseId = presentation.collapseId {
            content.userInfo = [PushNotificationHandler.collapseIdKey: collapseId]
        }
        return content
    }
}
