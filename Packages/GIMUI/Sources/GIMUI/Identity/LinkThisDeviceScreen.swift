import GIMFeatures
import SwiftUI
import UIKit

/// New device: links this device to an existing one by QR code (`startLink`, `waitLink`, `confirmLink`).
struct LinkThisDeviceScreen: View {
    @State private var viewModel: LinkThisDeviceViewModel
    /// Bumped by "Try again" to restart the link task.
    @State private var attempt = 0
    @Environment(\.dismiss) private var dismiss

    init(context: OnboardingContext) {
        _viewModel = State(initialValue: LinkThisDeviceViewModel(context: context))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                content
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(Text("Link device", tableName: "Devices", bundle: .module))
        .navigationBarBackButtonHidden(viewModel.isConfirming)
        .task(id: attempt) { await viewModel.start() }
        .onChange(of: viewModel.step) { _, step in
            if step == .rejected { dismiss() }
        }
        .onDisappear {
            Task { await viewModel.abandon() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.step {
        case .starting, .linked:
            ProgressView().padding(.top, 48)
        case .waiting(let qrString):
            waiting(qrString: qrString)
        case .comparing(let sas):
            comparing(sas: sas)
        case .failed(let message):
            ContentUnavailableView {
                Label(
                    String(localized: "Couldn't link", table: "Devices", bundle: .module),
                    systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button(String(localized: "Try again", table: "Common", bundle: .module)) { attempt += 1 }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("link.retry")
            }
        case .rejected:
            EmptyView()
        }
    }

    private func waiting(qrString: String) -> some View {
        VStack(spacing: 24) {
            Text(
                "On your other device, open Settings, choose Link a new device and scan this code.",
                tableName: "Devices", bundle: .module
            )
            .multilineTextAlignment(.center)
            QRCodeView(text: qrString)
                .frame(width: 240, height: 240)
                .padding(12)
                .background(.white, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("link.qr")
            Button {
                UIPasteboard.general.string = qrString
            } label: {
                Label(String(localized: "Copy link code", table: "Devices", bundle: .module), systemImage: "doc.on.doc")
            }
            .accessibilityHint(
                Text("Copies the code to paste on your other device", tableName: "Devices", bundle: .module)
            )
            .accessibilityIdentifier("link.copy")
            HStack(spacing: 8) {
                ProgressView()
                Text("Waiting for your other device…", tableName: "Devices", bundle: .module)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("link.waiting")
            Button(String(localized: "Cancel", table: "Common", bundle: .module), role: .cancel) { dismiss() }
                .accessibilityIdentifier("link.cancel")
        }
    }

    private func comparing(sas: String) -> some View {
        VStack(spacing: 24) {
            Text("Check that your other device shows the same code.", tableName: "Devices", bundle: .module)
                .multilineTextAlignment(.center)
            Text(sas)
                .font(.system(size: 44, weight: .semibold, design: .monospaced))
                .accessibilityIdentifier("link.sas")
            if let error = viewModel.errorMessage {
                Text(error).foregroundStyle(.red).multilineTextAlignment(.center)
            }
            if viewModel.isConfirming {
                ProgressView()
            }
            Button {
                confirm(codesMatch: true)
            } label: {
                Text("Codes match", tableName: "Devices", bundle: .module).bold().frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("link.match")
            Button(role: .destructive) {
                confirm(codesMatch: false)
            } label: {
                Text("Codes don't match", tableName: "Devices", bundle: .module).frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("link.mismatch")
        }
        .disabled(viewModel.isConfirming)
    }

    private func confirm(codesMatch: Bool) {
        Task { await viewModel.confirm(codesMatch: codesMatch) }
    }
}
