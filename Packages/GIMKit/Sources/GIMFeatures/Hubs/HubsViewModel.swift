import Foundation
import GIMClientKit
import Observation

/// The user's hubs (gim-core "Hub management"): follows `hubList`, makes a hub primary and removes hubs after a
/// confirmation, asking once more when the hub hosts groups the user owns.
///
/// The list is only changed by the subscription: after `setPrimaryHub` or `removeHub` gim-core reports the new list.
@MainActor
@Observable
public final class HubsViewModel {
    /// An alert explaining why a hub can't be removed (now).
    public struct Notice: Sendable, Hashable {
        public let title: String
        public let message: String
    }

    /// A removal waiting for the user to accept that the hub hosts groups they own (`HubOwnsGroups`).
    public struct OwnedGroupsWarning: Sendable, Hashable {
        public let hub: HubInfo
        public let groupCount: UInt32
        public let message: String
    }

    /// Listed hubs (primary first), then removed ones.
    public private(set) var hubs: [HubInfo] = []
    /// True until the first list arrives.
    public private(set) var isLoading = true
    /// The hub whose change is in flight.
    public private(set) var busyHubId: String?
    /// Error from subscribing or from the last failed change, shown under the list.
    public private(set) var errorMessage: String?
    /// Hub waiting for the user to confirm its removal.
    public private(set) var pendingRemoval: HubInfo?
    public private(set) var ownedGroupsWarning: OwnedGroupsWarning?
    public private(set) var notice: Notice?

    private let client: any GimClientAPI
    @ObservationIgnored private var listTask: Task<Void, Never>?

    public init(client: any GimClientAPI) {
        self.client = client
    }

    deinit {
        listTask?.cancel()
    }

    /// Subscribes to the hub list. Does nothing while already subscribed.
    public func start() {
        guard listTask == nil else { return }
        let client = client
        listTask = Task { [weak self] in
            do {
                for await hubs in try await ListenerBridge.hubList(client) {
                    self?.apply(hubs)
                }
            } catch {
                self?.isLoading = false
                self?.errorMessage = ErrorPresenter.message(for: error)
            }
        }
    }

    public func stop() {
        listTask?.cancel()
        listTask = nil
    }

    /// A verified hub this device is signed in to can become the primary hub.
    public func canSetPrimary(_ hub: HubInfo) -> Bool {
        !hub.isPrimary && hub.state == .verified && hub.signedIn && busyHubId == nil
    }

    /// Every listed hub offers removal; gim-core explains why the home or the last hub stays.
    public func canRemove(_ hub: HubInfo) -> Bool {
        hub.state != .removed && busyHubId == nil
    }

    public func setPrimary(hubId: String) async {
        guard let hub = hubs.first(where: { $0.hubId == hubId }), canSetPrimary(hub) else { return }
        await change(hubId) { try await $0.setPrimaryHub(hubId: hubId) }
    }

    /// Asks for confirmation before removing `hub`.
    public func requestRemoval(_ hub: HubInfo) {
        guard canRemove(hub) else { return }
        pendingRemoval = hub
    }

    public func cancelRemoval() {
        pendingRemoval = nil
    }

    /// Removes `hub` once the user confirmed `pendingRemoval`; a hub hosting own groups asks again
    /// (`ownedGroupsWarning`). Takes the confirmed hub because dismissing the dialog may clear `pendingRemoval` first.
    public func confirmRemoval(of hub: HubInfo) async {
        pendingRemoval = nil
        await remove(hub, confirmOwnedGroups: false)
    }

    /// Removes the hub of `warning` although it hosts groups the user owns.
    public func confirmOwnedGroupsRemoval(_ warning: OwnedGroupsWarning) async {
        ownedGroupsWarning = nil
        await remove(warning.hub, confirmOwnedGroups: true)
    }

    public func cancelOwnedGroupsRemoval() {
        ownedGroupsWarning = nil
    }

    public func dismissNotice() {
        notice = nil
    }

    public func dismissError() {
        errorMessage = nil
    }

    private func remove(_ hub: HubInfo, confirmOwnedGroups: Bool) async {
        let hubId = hub.hubId
        await change(hubId) { client in
            do {
                try await client.removeHub(hubId: hubId, confirmOwnedGroups: confirmOwnedGroups)
            } catch GimError.HubOwnsGroups(_, let groupCount) {
                self.ownedGroupsWarning = OwnedGroupsWarning(
                    hub: hub, groupCount: groupCount, message: Self.ownedGroupsMessage(groupCount))
            } catch let error as GimError {
                guard let title = Self.noticeTitle(error) else { throw error }
                self.notice = Notice(title: title, message: ErrorPresenter.message(for: error))
            }
        }
    }

    private func change(_ hubId: String, _ operation: (any GimClientAPI) async throws -> Void) async {
        guard busyHubId == nil else { return }
        busyHubId = hubId
        errorMessage = nil
        defer { busyHubId = nil }
        do {
            try await operation(client)
        } catch {
            errorMessage = await ErrorPresenter.message(for: error, client: client)
        }
    }

    private func apply(_ hubs: [HubInfo]) {
        isLoading = false
        self.hubs = hubs.filter { $0.state != .removed } + hubs.filter { $0.state == .removed }
    }

    static func ownedGroupsMessage(_ groupCount: UInt32) -> String {
        if groupCount == 1 {
            return NSLocalizedString(
                "This server hosts 1 group you own. Removing it doesn't move them: they keep running there, and you still reach them through your other servers.",
                tableName: "FeaturesHubs", bundle: FeaturesLocalization.bundle,
                value:
                    "This server hosts 1 group you own. Removing it doesn't move them: they keep running there, and you still reach them through your other servers.",
                comment: "")
        }
        let format = NSLocalizedString(
            "This server hosts %lld groups you own. Removing it doesn't move them: they keep running there, and you still reach them through your other servers.",
            tableName: "FeaturesHubs", bundle: FeaturesLocalization.bundle,
            value:
                "This server hosts %lld groups you own. Removing it doesn't move them: they keep running there, and you still reach them through your other servers.",
            comment: "")
        return String(format: format, Int(groupCount))
    }

    /// The alert title of removal errors that are explained rather than shown as a failure.
    static func noticeTitle(_ error: GimError) -> String? {
        switch error {
        case .HomeHub:
            NSLocalizedString(
                "Can't remove your main server", tableName: "FeaturesHubs", bundle: FeaturesLocalization.bundle,
                value: "Can't remove your main server", comment: "")
        case .LastHub:
            NSLocalizedString(
                "Can't remove your only server", tableName: "FeaturesHubs", bundle: FeaturesLocalization.bundle,
                value: "Can't remove your only server", comment: "")
        case .HubNotDrained:
            NSLocalizedString(
                "Try again later", tableName: "FeaturesHubs", bundle: FeaturesLocalization.bundle,
                value: "Try again later", comment: "")
        default: nil
        }
    }

    // MARK: - Row text

    /// What a row shows for `hub`: the URL's host (and port), else the start of the hub id.
    public nonisolated static func address(of hub: HubInfo) -> String {
        if let url = hub.url, let components = URLComponents(string: url), let host = components.host,
            !host.isEmpty
        {
            return host.lowercased() + (components.port.map { ":\($0)" } ?? "")
        }
        return hub.hubId.count > 16 ? "\(hub.hubId.prefix(12))…" : hub.hubId
    }

    public nonisolated static func stateText(_ state: HubState) -> String {
        switch state {
        case .unverified:
            NSLocalizedString(
                "Not checked", tableName: "FeaturesHubs", bundle: FeaturesLocalization.bundle, value: "Not checked",
                comment: "")
        case .verified:
            NSLocalizedString(
                "Connected", tableName: "FeaturesHubs", bundle: FeaturesLocalization.bundle, value: "Connected",
                comment: "")
        case .removed:
            NSLocalizedString(
                "Removed", tableName: "FeaturesHubs", bundle: FeaturesLocalization.bundle, value: "Removed",
                comment: "")
        }
    }
}
