import Foundation
import GIMClientKit
import Observation

/// Old device side of a device link: approves the link code scanned or pasted from the new device, then has the user
/// compare the SAS. Follows gim-core's call order: `approveLink`, `confirmApproval`, and `revokeDevice` when the user
/// leaves in between.
@MainActor
@Observable
public final class ApproveLinkViewModel {
    public enum Outcome: Equatable, Sendable {
        /// The new device was added to every joined chat.
        case linked
        /// The new device was revoked.
        case rejected
    }

    /// The pasted link code.
    public var linkCode = ""

    public private(set) var isWorking = false
    /// Error from the last failed step.
    public private(set) var errorMessage: String?
    /// The SAS to compare with the new device's; set once the link was approved.
    public private(set) var sas: String?
    /// The new device; set once the link was approved.
    public private(set) var newDeviceId: String?
    public private(set) var outcome: Outcome?

    private let client: any GimClientAPI
    /// Approved but neither confirmed nor rejected yet.
    @ObservationIgnored private var approval: (any PendingApproval)?

    public init(client: any GimClientAPI) {
        self.client = client
    }

    /// Whether a link code can be approved: not while working or once a link was approved.
    public var canApprove: Bool { !isWorking && sas == nil && outcome == nil }

    /// Approves the pasted link code.
    public func submit() async {
        await approve(qrString: linkCode)
    }

    /// Approves a scanned or pasted link code.
    public func approve(qrString: String) async {
        guard canApprove else { return }
        let code = qrString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            errorMessage = "Paste the link code shown on your new device."
            return
        }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let approval = try await client.approveLink(qrString: code)
            self.approval = approval
            newDeviceId = approval.deviceId()
            sas = approval.sas()
        } catch {
            errorMessage = await ErrorPresenter.message(for: error, client: client)
        }
    }

    /// Reports the user's SAS comparison: a match adds the new device to every chat, a mismatch revokes it.
    public func confirm(codesMatch: Bool) async {
        guard let approval, !isWorking else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await client.confirmApproval(approval: approval, accepted: codesMatch)
            self.approval = nil
            outcome = codesMatch ? .linked : .rejected
        } catch {
            errorMessage = await ErrorPresenter.message(for: error, client: client)
        }
    }

    /// The user left after approving without confirming: revokes the listed but unused new device (best effort).
    public func abandon() async {
        guard let approval, !isWorking else { return }
        self.approval = nil
        try? await client.revokeDevice(deviceId: approval.deviceId())
    }
}
