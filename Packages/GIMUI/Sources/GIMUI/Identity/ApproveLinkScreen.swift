import GIMClientKit
import SwiftUI

/// Old device: scans a new device's QR code and approves the link (`approveLink`, `confirmApproval`).
///
/// Placeholder: the flow lands in a later change.
struct ApproveLinkScreen: View {
    let client: any GimClientAPI

    var body: some View {
        ContentUnavailableView(
            "Coming Soon", systemImage: "qrcode.viewfinder",
            description: Text("Linking a new device isn't available yet.")
        )
        .navigationTitle("Link a New Device")
    }
}
