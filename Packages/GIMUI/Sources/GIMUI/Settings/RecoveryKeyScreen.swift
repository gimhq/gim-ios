import GIMFeatures
import LocalAuthentication
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Settings → Recovery key: shows the recovery key kept on this device like a wallet seed phrase. Nothing is shown
/// before the device owner authenticated (biometrics or the device passcode). While shown, the key and its QR code sit
/// in a layer the system leaves out of screenshots and recordings, and the key is hidden again when the screen is
/// captured or mirrored, after a screenshot, when the app leaves the foreground and when the screen closes. A device
/// without the key offers a new one (the rotation flow with its ending check), which can then be shown here.
struct RecoveryKeyScreen: View {
    @State private var viewModel: RecoveryKeyViewModel
    @State private var isCaptured = Self.screenIsCaptured
    @State private var showsCopied = false
    @Environment(\.scenePhase) private var scenePhase

    /// The kit as a file for the share sheet; written while the key is shown.
    private let kitFileUrl = FileManager.default.temporaryDirectory.appendingPathComponent("gim-recovery-kit.txt")

    init(viewModel: RecoveryKeyViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Form {
            switch viewModel.state {
            case .locked, .authenticating:
                lockedSection
            case .shown:
                if isCaptured {
                    capturedSection
                } else {
                    keySections
                }
            case .notOnThisDevice:
                notOnThisDeviceSection
            }
        }
        .navigationTitle(Text("Recovery key", tableName: "Settings", bundle: .module))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if viewModel.state == .shown {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        viewModel.hide()
                    } label: {
                        Text("Hide", tableName: "Settings", bundle: .module)
                    }
                    .accessibilityIdentifier("recoveryKey.hide")
                }
            }
        }
        .onChange(of: viewModel.state) { _, state in
            if state == .shown {
                try? viewModel.kitText.write(to: kitFileUrl, atomically: true, encoding: .utf8)
            } else {
                try? FileManager.default.removeItem(at: kitFileUrl)
            }
        }
        // The authentication prompt makes the scene inactive; only a shown key is hidden then.
        .onChange(of: scenePhase) { _, phase in
            if phase == .background || (phase != .active && viewModel.state == .shown) { hide() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)) { note in
            isCaptured = (note.object as? UIScreen)?.isCaptured ?? Self.screenIsCaptured
            if isCaptured { hide() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.userDidTakeScreenshotNotification)) { _ in
            hide()
        }
        .onDisappear(perform: hide)
        .alert(
            Text("Create a new recovery key?", tableName: "Settings", bundle: .module),
            isPresented: Binding(
                get: { viewModel.rotation.state == .confirming },
                set: { presented in if !presented { viewModel.rotation.cancel() } })
        ) {
            Button {
                Task { await viewModel.rotation.rotate() }
            } label: {
                Text("Create new key", tableName: "Settings", bundle: .module)
            }
            .accessibilityIdentifier("recoveryKey.newKey.create")
            Button(role: .cancel) {
                viewModel.rotation.cancel()
            } label: {
                Text("Cancel", tableName: "Common", bundle: .module)
            }
        } message: {
            Text(
                "Your current recovery key stops working. The new recovery kit replaces the old one, so save it again.",
                tableName: "Settings", bundle: .module)
        }
        // The new kit stays until the user confirmed its ending; `RecoveryKitScreen` hides the back button.
        .navigationDestination(isPresented: Binding(get: { viewModel.rotation.kit != nil }, set: { _ in })) {
            if let kit = viewModel.rotation.kit {
                RecoveryKitScreen(viewModel: kit)
            }
        }
    }

    private var lockedSection: some View {
        Section {
            Button {
                Task { await viewModel.reveal() }
            } label: {
                HStack {
                    Label {
                        Text("Show recovery key", tableName: "Settings", bundle: .module)
                    } icon: {
                        Image(systemName: "lock")
                    }
                    Spacer()
                    if viewModel.state == .authenticating { ProgressView() }
                }
            }
            .disabled(viewModel.state == .authenticating)
            .accessibilityIdentifier("recoveryKey.show")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(
                    "Your recovery key and Account ID bring your account back if you lose all your devices. Anyone who sees them can get into your account.",
                    tableName: "Settings", bundle: .module)
                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("recoveryKey.error")
                }
            }
        }
    }

    private var capturedSection: some View {
        Section {
            Label {
                Text("Hidden while your screen is recorded or shared.", tableName: "Settings", bundle: .module)
            } icon: {
                Image(systemName: "eye.slash")
            }
            .accessibilityIdentifier("recoveryKey.captured")
        }
    }

    @ViewBuilder
    private var keySections: some View {
        Section {
            ScreenshotProof {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Account ID", tableName: "Onboarding", bundle: .module)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text(viewModel.userId)
                            .font(.body.monospaced())
                            .accessibilityIdentifier("recoveryKey.userId")
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recovery key", tableName: "Onboarding", bundle: .module)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text(viewModel.groupedCode)
                            .font(.title3.monospaced())
                            .accessibilityLabel(viewModel.groupedCode)
                            .accessibilityIdentifier("recoveryKey.code")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } footer: {
            Text("explainer_recovery_key_body", tableName: "Explainer", bundle: .module)
        }

        Section {
            Button(action: copy) {
                Label {
                    if showsCopied {
                        Text("Copied", tableName: "Onboarding", bundle: .module)
                    } else {
                        Text("Copy", tableName: "Onboarding", bundle: .module)
                    }
                } icon: {
                    Image(systemName: showsCopied ? "checkmark" : "doc.on.doc")
                }
            }
            .accessibilityIdentifier("recoveryKey.copy")
            ShareLink(
                item: kitFileUrl,
                preview: SharePreview(Text("gim recovery kit", tableName: "Onboarding", bundle: .module))
            ) {
                Label {
                    Text("Save as a file", tableName: "Onboarding", bundle: .module)
                } icon: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
            .accessibilityIdentifier("recoveryKey.share")
        }

        Section {
            ScreenshotProof {
                QRCodeView(text: viewModel.kitText)
                    .frame(width: 220, height: 220)
                    .padding(12)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(Text("Recovery kit QR code", tableName: "Settings", bundle: .module))
                    .accessibilityIdentifier("recoveryKey.qr")
            }
        } header: {
            Text("Recovery kit QR code", tableName: "Settings", bundle: .module)
        } footer: {
            Text(
                "It holds your Account ID and recovery key. Keep it as private as the key.", tableName: "Settings",
                bundle: .module)
        }
    }

    private var notOnThisDeviceSection: some View {
        Section {
            Label {
                Text("This device doesn't have your recovery key", tableName: "Settings", bundle: .module)
            } icon: {
                Image(systemName: "key.slash")
            }
            .accessibilityIdentifier("recoveryKey.notOnThisDevice")
            Button {
                viewModel.rotation.start()
            } label: {
                HStack {
                    Text("Create a new recovery key", tableName: "Settings", bundle: .module)
                    Spacer()
                    if viewModel.rotation.state == .rotating { ProgressView() }
                }
            }
            .disabled(viewModel.rotation.state == .rotating)
            .accessibilityIdentifier("recoveryKey.newKey")
        } footer: {
            if case .failed(let message) = viewModel.rotation.state {
                Text(message).foregroundStyle(.red)
            } else {
                Text(
                    "It was made on another device. Create a new one to keep it here too. Your current key then stops working.",
                    tableName: "Settings", bundle: .module)
            }
        }
    }

    private func hide() {
        showsCopied = false
        viewModel.hide()
        try? FileManager.default.removeItem(at: kitFileUrl)
    }

    /// Copies the kit for this device only, clears it from the pasteboard after two minutes, and shows "Copied" for
    /// two seconds.
    private func copy() {
        UIPasteboard.general.setItems(
            [[UTType.plainText.identifier: viewModel.kitText]],
            options: [.localOnly: true, .expirationDate: Date.now.addingTimeInterval(120)])
        showsCopied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            showsCopied = false
        }
    }

    private static var screenIsCaptured: Bool {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen }.contains(where: \.isCaptured)
    }
}

/// Hosts `content` in the secure layer of a `UITextField` with `isSecureTextEntry`, which the system leaves out of
/// screenshots, screen recordings and mirroring. Falls back to a plain container where that layer is not found.
struct ScreenshotProof<Content: View>: UIViewRepresentable {
    @ViewBuilder let content: () -> Content

    func makeCoordinator() -> UIHostingController<Content> {
        let host = UIHostingController(rootView: content())
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        return host
    }

    func makeUIView(context: Context) -> UIView {
        let field = UITextField()
        field.isSecureTextEntry = true
        let container =
            field.subviews.first { String(describing: type(of: $0)).contains("CanvasView") } ?? UIView()
        container.subviews.forEach { $0.removeFromSuperview() }
        container.removeFromSuperview()
        container.isUserInteractionEnabled = true
        container.addSubview(context.coordinator.view)
        NSLayoutConstraint.activate([
            context.coordinator.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            context.coordinator.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            context.coordinator.view.topAnchor.constraint(equalTo: container.topAnchor),
            context.coordinator.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.rootView = content()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIView, context: Context) -> CGSize? {
        context.coordinator.sizeThatFits(
            in: CGSize(
                width: proposal.width ?? UIView.layoutFittingExpandedSize.width,
                height: proposal.height ?? UIView.layoutFittingExpandedSize.height))
    }
}

/// Device owner authentication with LocalAuthentication (`.deviceOwnerAuthentication`: biometrics, else the device
/// passcode). Debug builds launched with `-GIMSkipDeviceAuth YES` (UI tests on simulators without a passcode) skip it.
struct LocalDeviceAuthenticator: DeviceAuthenticator {
    static let skipKey = "GIMSkipDeviceAuth"

    func authenticate(reason: String) async -> DeviceAuthResult {
        #if DEBUG
            if UserDefaults.standard.bool(forKey: Self.skipKey) { return .success }
        #endif
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return .unavailable }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
                ? .success : .failed
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .appCancel, .systemCancel: return .cancelled
            case .passcodeNotSet, .biometryNotAvailable, .biometryNotEnrolled: return .unavailable
            default: return .failed
            }
        } catch {
            return .failed
        }
    }
}
