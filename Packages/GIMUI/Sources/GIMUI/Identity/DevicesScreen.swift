import GIMClientKit
import SwiftUI

/// The signed-in user's devices (`devices`, `revokeDevice`).
///
/// Placeholder: the list lands in a later change.
struct DevicesScreen: View {
    let client: any GimClientAPI

    var body: some View {
        ContentUnavailableView(
            "Coming Soon", systemImage: "laptopcomputer.and.iphone",
            description: Text("The device list isn't available yet.")
        )
        .navigationTitle("Devices")
    }
}
