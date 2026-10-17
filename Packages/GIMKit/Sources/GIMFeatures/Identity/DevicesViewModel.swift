import Foundation
import GIMClientKit
import Observation

/// The signed-in user's devices: lists them (this device first, revoked ones last) and revokes other active ones.
@MainActor
@Observable
public final class DevicesViewModel {
    public private(set) var devices: [DeviceInfo] = []
    /// Whether `devices` holds the result of a successful load.
    public private(set) var hasLoaded = false
    public private(set) var isLoading = false
    /// The device whose revocation is in flight.
    public private(set) var revokingDeviceId: String?
    /// Error from the last failed load or revocation.
    public private(set) var errorMessage: String?

    private let client: any GimClientAPI

    public init(client: any GimClientAPI) {
        self.client = client
    }

    /// The signed-in user's id; `nil` without a session.
    public var userId: String? { client.userId() }

    /// Only other active devices can be revoked.
    public func canRevoke(_ device: DeviceInfo) -> Bool {
        !device.isCurrent && !device.revoked && revokingDeviceId == nil
    }

    public func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            devices = Self.sorted(try await client.devices())
            hasLoaded = true
            errorMessage = nil
        } catch {
            errorMessage = await ErrorPresenter.message(for: error, client: client)
        }
    }

    /// Revokes `deviceId` and reloads the list; does nothing for this device, a revoked or an unknown one.
    public func revoke(deviceId: String) async {
        guard let device = devices.first(where: { $0.deviceId == deviceId }), canRevoke(device) else { return }
        revokingDeviceId = deviceId
        errorMessage = nil
        defer { revokingDeviceId = nil }
        do {
            try await client.revokeDevice(deviceId: deviceId)
        } catch {
            errorMessage = await ErrorPresenter.message(for: error, client: client)
            return
        }
        await load()
    }

    public func dismissError() {
        errorMessage = nil
    }

    /// This device first, then the other active devices, then the revoked ones; newest first within each group.
    static func sorted(_ devices: [DeviceInfo]) -> [DeviceInfo] {
        func rank(_ device: DeviceInfo) -> Int { device.isCurrent ? 0 : device.revoked ? 2 : 1 }
        return devices.sorted {
            rank($0) != rank($1) ? rank($0) < rank($1) : $0.createdAtMs > $1.createdAtMs
        }
    }
}
