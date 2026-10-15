import GIMClientKit
import GIMFeatures
import SwiftUI
import UIKit

/// The signed-in user's devices (`devices`, `revokeDevice`): this device, the other active ones (revocable after a
/// confirmation) and the revoked ones.
struct DevicesScreen: View {
    let client: any GimClientAPI

    @State private var viewModel: DevicesViewModel
    @State private var revokeCandidate: DeviceInfo?

    init(client: any GimClientAPI) {
        self.client = client
        _viewModel = State(initialValue: DevicesViewModel(client: client))
    }

    var body: some View {
        List {
            if let userId = viewModel.userId {
                Section {
                    Button {
                        UIPasteboard.general.string = userId
                    } label: {
                        LabeledContent("User ID") {
                            HStack {
                                Text(userId).lineLimit(1).truncationMode(.middle)
                                Image(systemName: "doc.on.doc")
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                    .accessibilityHint("Copies the user ID")
                    .accessibilityIdentifier("devices.userId")
                } footer: {
                    Text("You need the user ID and your recovery code to restore your identity.")
                }
            }
            Section {
                ForEach(viewModel.devices, id: \.deviceId) { device in
                    row(device)
                }
            } footer: {
                if let error = viewModel.errorMessage {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
        .accessibilityIdentifier("devices.list")
        .overlay {
            if viewModel.devices.isEmpty && viewModel.isLoading {
                ProgressView()
            }
        }
        .refreshable { await viewModel.load() }
        .task { await viewModel.load() }
        .navigationTitle("Devices")
        .confirmationDialog(
            "Revoke this device?", isPresented: revokeDialogPresented, titleVisibility: .visible,
            presenting: revokeCandidate
        ) { device in
            Button("Revoke", role: .destructive) {
                Task { await viewModel.revoke(deviceId: device.deviceId) }
            }
        } message: { _ in
            Text("It will be signed out and removed from all your chats. This can't be undone.")
        }
    }

    private func row(_ device: DeviceInfo) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(device.deviceId).lineLimit(1).truncationMode(.middle)
                Group {
                    if device.isCurrent {
                        Text("This device").accessibilityIdentifier("devices.current")
                    } else if device.revoked {
                        Text("Revoked")
                    } else {
                        Text("Active")
                    }
                }
                .font(.footnote)
                .foregroundStyle(device.isCurrent ? Color.accentColor : .secondary)
                if device.createdAtMs > 0 {
                    Text(
                        "Added \(Date(epochMilliseconds: device.createdAtMs).formatted(date: .abbreviated, time: .omitted))"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if viewModel.revokingDeviceId == device.deviceId {
                ProgressView()
            } else if viewModel.canRevoke(device) {
                Button("Revoke", role: .destructive) { revokeCandidate = device }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("devices.revoke.\(device.deviceId)")
            }
        }
        .foregroundStyle(device.revoked ? .secondary : .primary)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("devices.row.\(device.deviceId)")
    }

    private var revokeDialogPresented: Binding<Bool> {
        Binding(get: { revokeCandidate != nil }, set: { if !$0 { revokeCandidate = nil } })
    }
}
