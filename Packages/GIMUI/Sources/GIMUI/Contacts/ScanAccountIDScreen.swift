import AVFoundation
import SwiftUI
import UIKit

/// Scans a friend's Account ID QR code, or takes a typed Account ID, and hands the text to `onScanned`. The caller
/// starts the chat and reports a failure through `error`; "Try again" clears it and restarts the camera, because the
/// scanner reports a code held in front of it only once.
struct ScanAccountIDScreen: View {
    @Binding var error: String?
    var isWorking = false
    let onScanned: (String) -> Void

    @State private var cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
    /// Recreates the scanner so the same code can be scanned again.
    @State private var scanAttempt = 0
    @State private var typedId = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    camera
                    Text(
                        "Point the camera at your friend's QR code from their Settings.", tableName: "Contacts",
                        bundle: .module
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    if isWorking {
                        ProgressView()
                    } else if let error {
                        VStack(spacing: 8) {
                            Text(error)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                                .accessibilityIdentifier("newChat.scan.error")
                            Button(String(localized: "Try again", table: "Common", bundle: .module)) {
                                self.error = nil
                                scanAttempt += 1
                            }
                        }
                    }
                    typedEntry
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(Text("Scan QR code", tableName: "Contacts", bundle: .module))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", table: "Common", bundle: .module)) { dismiss() }
                }
            }
        }
    }

    /// The simulator has no camera: only the typed entry is shown there.
    private var hasCamera: Bool { AVCaptureDevice.default(for: .video) != nil }

    @ViewBuilder
    private var camera: some View {
        if hasCamera {
            switch cameraStatus {
            case .authorized:
                QRScannerView { code in onScanned(code) }
                    .id(scanAttempt)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel(Text("Camera", tableName: "Contacts", bundle: .module))
            case .notDetermined:
                Text("Allow camera access to scan your friend's code.", tableName: "Contacts", bundle: .module)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button(String(localized: "Allow camera", table: "Contacts", bundle: .module)) {
                    Task {
                        _ = await AVCaptureDevice.requestAccess(for: .video)
                        cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
                    }
                }
                .buttonStyle(.borderedProminent)
            default:
                Text(
                    "gim can't use the camera. Allow camera access in the system settings.", tableName: "Contacts",
                    bundle: .module
                )
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                Button(String(localized: "Open settings", table: "Contacts", bundle: .module)) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
        }
    }

    private var typedEntry: some View {
        HStack {
            TextField(text: $typedId) {
                Text("Account ID", tableName: "Contacts", bundle: .module)
            }
            .textFieldStyle(.roundedBorder)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.go)
            .onSubmit(submitTyped)
            .accessibilityIdentifier("newChat.scan.field")
            Button(String(localized: "Start chat", table: "Contacts", bundle: .module), action: submitTyped)
                .disabled(typedId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking)
                .accessibilityIdentifier("newChat.scan.submit")
        }
    }

    private func submitTyped() {
        guard !isWorking else { return }
        onScanned(typedId)
    }
}

#Preview {
    ScanAccountIDScreen(error: .constant("This code is not a gim Account ID.")) { _ in }
}
