import SwiftUI
import UIKit

/// Shows the user's Account ID as a QR code for friends to scan.
struct MyQRCodeScreen: View {
    let userId: String

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                QRCodeView(text: userId)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: 280)
                    .padding()
                Text(userId)
                    .font(.system(.footnote, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("settings.qrCode.userId")
                Text("Friends scan this to start a chat with you.", tableName: "Settings", bundle: .module)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button {
                    UIPasteboard.general.string = userId
                } label: {
                    Text("Copy", tableName: "Common", bundle: .module)
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
        .navigationTitle(Text("My QR code", tableName: "Settings", bundle: .module))
        .navigationBarTitleDisplayMode(.inline)
    }
}
