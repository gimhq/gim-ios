import GIMFeatures
import SwiftUI

/// New device: links this device to an existing one by QR code (`startLink`, `waitLink`, `confirmLink`).
///
/// Placeholder: the flow lands in a later change. Get the client from `context.client()`, drop it with
/// `context.discardClient()` after `confirmLink(accepted: false)`, and finish with `context.onRegistered`.
struct LinkThisDeviceScreen: View {
    let context: OnboardingContext

    var body: some View {
        ContentUnavailableView(
            "Coming Soon", systemImage: "qrcode",
            description: Text("Linking to an existing device isn't available yet.")
        )
        .navigationTitle("Link Device")
    }
}
