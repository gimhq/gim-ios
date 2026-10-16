import Foundation
import GIMClientKit
import Observation

/// New device side of a device link: shows a link offer for the chosen server until the old device approved it, then
/// has the user compare the SAS. Follows gim-core's call order: `startLink`, `waitLink`, `confirmLink`.
@MainActor
@Observable
public final class LinkThisDeviceViewModel {
    public enum Step: Equatable, Sendable {
        /// Creating the client and the link offer.
        case starting
        /// Showing the offer while `waitLink` waits (up to 10 minutes) for the old device.
        case waiting(qrString: String)
        /// This device is signed in; the user compares `sas` with the one on the old device.
        case comparing(sas: String)
        /// Starting or waiting failed; `start()` waits again for the same link offer, or begins a new one once a
        /// bundle arrived.
        case failed(message: String)
        /// The user rejected the SAS and the device wiped itself; go back to the onboarding start.
        case rejected
        /// The link is confirmed and the client was handed to `OnboardingContext.onRegistered`.
        case linked
    }

    public private(set) var step: Step = .starting
    public private(set) var isConfirming = false
    /// Error from the last failed confirmation; the user can answer again.
    public private(set) var errorMessage: String?

    private let context: OnboardingContext
    @ObservationIgnored private var client: (any GimClientAPI)?
    /// The offer of `client` waited for last; `nil` before the first one.
    @ObservationIgnored private var link: (any LinkSession)?

    public init(context: OnboardingContext) {
        self.context = context
    }

    /// Waits for the old device to approve the current link offer, starting one first if there is none; does nothing
    /// once the SAS is shown. A cancelled wait returns to `.starting`.
    ///
    /// A failed `waitLink` keeps nothing of the attempt. Without a bundle (network error, timeout) the same offer
    /// can wait again; once a bundle arrived the offer is used up and gim-core rejects it with `InvalidInput`, so a
    /// new offer (new QR code) is started for the old device to approve again.
    public func start() async {
        switch step {
        case .starting, .failed: break
        case .waiting, .comparing, .rejected, .linked: return
        }
        step = .starting
        do {
            let client = try await context.client()
            if client !== self.client { link = nil }
            self.client = client
            let sas: String
            if let link {
                do {
                    sas = try await waitLink(client, link)
                } catch GimError.InvalidInput {
                    sas = try await waitLink(client, startLink(client))
                }
            } else {
                sas = try await waitLink(client, startLink(client))
            }
            step = .comparing(sas: sas)
        } catch {
            step = Task.isCancelled ? .starting : .failed(message: ErrorPresenter.message(for: error))
        }
    }

    /// Reports the user's SAS comparison: a match completes the link and signs in, a mismatch wipes the device
    /// (`confirmLink(accepted: false)`) and drops its client so the next attempt creates a new one.
    public func confirm(codesMatch: Bool) async {
        guard case .comparing = step, let client, !isConfirming else { return }
        isConfirming = true
        errorMessage = nil
        defer { isConfirming = false }
        do {
            try await client.confirmLink(accepted: codesMatch)
            guard codesMatch else {
                self.client = nil
                link = nil
                context.discardClient()
                step = .rejected
                return
            }
            guard let session = try await client.session() else { throw GimError.NotRegistered }
            step = .linked
            context.onRegistered(Registration(client: client, config: context.config, session: session))
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    private func startLink(_ client: any GimClientAPI) throws -> any LinkSession {
        let link = try client.startLink(hubs: [context.config.serverUrl])
        self.link = link
        return link
    }

    /// Shows `link` and waits for the old device to approve it.
    private func waitLink(_ client: any GimClientAPI, _ link: any LinkSession) async throws -> String {
        step = .waiting(qrString: link.qrString())
        return try await client.waitLink(link: link)
    }

    /// The user left before comparing the SAS: rejects the link (best effort) so the half-linked device is wiped.
    public func abandon() async {
        guard case .comparing = step, !isConfirming else { return }
        await confirm(codesMatch: false)
    }
}
