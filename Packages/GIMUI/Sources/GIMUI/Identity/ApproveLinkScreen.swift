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
        .navigationTitle("Link a New Device")
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
                    .accessibilityLabel("Camera")
                case .notDetermined:
                    Text("Allow camera access to scan the code.")
                        .foregroundStyle(.secondary)
                        .task {
                            _ = await AVCaptureDevice.requestAccess(for: .video)
                            cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
                        }
                default:
                    Text("GIM can't use the camera. Allow camera access in Settings or paste the link code below.")
                        .foregroundStyle(.secondary)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
            } header: {
                Text("Scan")
            } footer: {
                Text("On your new device, choose Link to an Existing Device and scan the code it shows.")
            }
        }
    }

    private var paste: some View {
        Section {
            TextField("Paste link code", text: $viewModel.linkCode)
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
                        Text("Link Device").bold()
                    }
                    Spacer()
                }
            }
            .disabled(!viewModel.canApprove)
            .accessibilityIdentifier("approve.submit")
        } header: {
            Text("Or paste the code")
        } footer: {
            if let error = viewModel.errorMessage {
                Text(error).foregroundStyle(.red)
            } else {
                Text("Use Copy Link Code on your new device and paste the code here.")
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
                    LabeledContent("New device", value: deviceId)
                }
            } footer: {
                Text("Check that your new device shows the same code.")
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
                            Text("Codes Match").bold()
                        }
                        Spacer()
                    }
                }
                .accessibilityIdentifier("approve.match")
                Button("Codes Don't Match", role: .destructive) { confirm(codesMatch: false) }
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
                Label("Device linked. It will join your chats on its next sync.", systemImage: "checkmark.circle")
            case .rejected:
                Label(
                    "The new device was removed. Choose Codes Don't Match on it too.",
                    systemImage: "xmark.circle")
            }
            Button("Done") { dismiss() }
                .accessibilityIdentifier("approve.done")
        }
    }
}
