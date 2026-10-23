import AVFoundation
import GIMClientKit
import GIMFeatures
import SwiftUI
import UIKit

/// Old device: scans or pastes a new device's link code and approves the link (`approveLink`, `confirmApproval`).
/// Leaving after approving without confirming revokes the new device.
struct ApproveLinkScreen: View {
    @State private var viewModel: ApproveLinkViewModel
    @State private var cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @FocusState private var focusesCode: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    init(client: any GimClientAPI) {
        _viewModel = State(initialValue: ApproveLinkViewModel(client: client))
    }

    var body: some View {
        Form {
            if let outcome = viewModel.outcome {
                done(outcome)
            } else if let sas = viewModel.sas {
                comparing(sas: sas)
            } else {
                scanner
                paste
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(Text("Link a new device", tableName: "Devices", bundle: .module))
        .navigationBarBackButtonHidden(viewModel.isWorking)
        .onDisappear {
            Task { await viewModel.abandon() }
        }
    }

    // MARK: - Code entry

    /// The simulator has no camera: only the paste field is shown there.
    private var hasCamera: Bool { AVCaptureDevice.default(for: .video) != nil }

    @ViewBuilder
    private var scanner: some View {
        if hasCamera {
            Section {
                switch cameraStatus {
                case .authorized:
                    QRScannerView { code in
                        Task { await viewModel.approve(qrString: code) }
                    }
                    .frame(height: 280)
                    .listRowInsets(EdgeInsets())
                    .accessibilityLabel(Text("Camera", tableName: "Devices", bundle: .module))
                case .notDetermined:
                    Text("Allow camera access to scan the code.", tableName: "Devices", bundle: .module)
                        .foregroundStyle(.secondary)
                        .task {
                            _ = await AVCaptureDevice.requestAccess(for: .video)
                            cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
                        }
                default:
                    Text(
                        "GIM can't use the camera. Allow camera access in Settings or paste the link code below.",
                        tableName: "Devices", bundle: .module)
                        .foregroundStyle(.secondary)
                    Button(String(localized: "Open Settings", table: "Devices", bundle: .module)) {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
            } header: {
                Text("Scan", tableName: "Devices", bundle: .module)
            } footer: {
                Text(
                    "On your new device, choose Link to an existing device and scan the code it shows.",
                    tableName: "Devices", bundle: .module)
            }
        }
    }

    private var paste: some View {
        Section {
            TextField(text: $viewModel.linkCode) {
                Text("Paste link code", tableName: "Devices", bundle: .module)
            }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusesCode)
                .accessibilityIdentifier("approve.paste")
                .submitLabel(.go)
                .onSubmit(submit)
            Button(action: submit) {
                HStack {
                    Spacer()
                    if viewModel.isWorking {
                        ProgressView()
                    } else {
                        Text("Link device", tableName: "Devices", bundle: .module).bold()
                    }
                    Spacer()
                }
            }
            .disabled(!viewModel.canApprove)
            .accessibilityIdentifier("approve.submit")
        } header: {
            Text("Or paste the code", tableName: "Devices", bundle: .module)
        } footer: {
            if let error = viewModel.errorMessage {
                Text(error).foregroundStyle(.red)
            } else {
                Text(
                    "On your new device, tap Copy link code, then paste it here.", tableName: "Devices", bundle: .module)
            }
        }
    }

    private func submit() {
        focusesCode = false
        Task { await viewModel.submit() }
    }

    // MARK: - SAS comparison

    private func comparing(sas: String) -> some View {
        Group {
            Section {
                Text(sas)
                    .font(.system(size: 44, weight: .semibold, design: .monospaced))
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("approve.sas")
                if let deviceId = viewModel.newDeviceId {
                    LabeledContent {
                        Text(deviceId)
                    } label: {
                        Text("New device", tableName: "Devices", bundle: .module)
                    }
                }
            } footer: {
                Text("Check that your new device shows the same code.", tableName: "Devices", bundle: .module)
            }
            Section {
                Button {
                    confirm(codesMatch: true)
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.isWorking {
                            ProgressView()
                        } else {
                            Text("Codes match", tableName: "Devices", bundle: .module).bold()
                        }
                        Spacer()
                    }
                }
                .accessibilityIdentifier("approve.match")
                Button(String(localized: "Codes don't match", table: "Devices", bundle: .module), role: .destructive) {
                    confirm(codesMatch: false)
                }
                .accessibilityIdentifier("approve.mismatch")
            } footer: {
                if let error = viewModel.errorMessage {
                    Text(error).foregroundStyle(.red)
                }
            }
            .disabled(viewModel.isWorking)
        }
    }

    private func confirm(codesMatch: Bool) {
        Task { await viewModel.confirm(codesMatch: codesMatch) }
    }

    // MARK: - Outcome

    private func done(_ outcome: ApproveLinkViewModel.Outcome) -> some View {
        Section {
            switch outcome {
            case .linked:
                Label(
                    String(
                        localized: "Device linked. It will join your chats on its next sync.", table: "Devices",
                        bundle: .module),
                    systemImage: "checkmark.circle")
            case .rejected:
                Label(
                    String(
                        localized: "The new device was removed. Choose Codes don't match on it too.", table: "Devices",
                        bundle: .module),
                    systemImage: "xmark.circle")
            }
            Button(String(localized: "Done", table: "Common", bundle: .module)) { dismiss() }
                .accessibilityIdentifier("approve.done")
        }
    }
}
