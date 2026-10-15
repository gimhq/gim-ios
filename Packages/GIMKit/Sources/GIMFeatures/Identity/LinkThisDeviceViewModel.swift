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
        /// Starting or waiting failed; `start()` begins a new link offer.
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

    public init(context: OnboardingContext) {
        self.context = context
    }

    /// Starts a new link offer and waits for the old device; does nothing once the SAS is shown. A cancelled wait
    /// returns to `.starting`.
    public func start() async {
        switch step {
        case .starting, .failed: break
        case .waiting, .comparing, .rejected, .linked: return
        }
        step = .starting
        do {
            let client = try await context.client()
            self.client = client
            // A link session accepts a single bundle, so every attempt starts a new one.
            let link = try client.startLink(hubs: [context.config.serverUrl])
            step = .waiting(qrString: link.qrString())
            let sas = try await client.waitLink(link: link)
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

    /// The user left before comparing the SAS: rejects the link (best effort) so the half-linked device is wiped.
    public func abandon() async {
        guard case .comparing = step, !isConfirming else { return }
        await confirm(codesMatch: false)
    }
}
