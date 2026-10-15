import GIMFeatures
import SwiftUI

/// Restores the user on this device from the recovery code (`restoreFromRecovery`).
///
/// Placeholder: the flow lands in a later change. Get the client from `context.client()` and finish with
/// `context.onRegistered`.
struct RestoreScreen: View {
    let context: OnboardingContext

    var body: some View {
        ContentUnavailableView(
            "Coming Soon", systemImage: "key",
            description: Text("Restoring from a recovery code isn't available yet.")
        )
        .navigationTitle("Restore")
    }
}
