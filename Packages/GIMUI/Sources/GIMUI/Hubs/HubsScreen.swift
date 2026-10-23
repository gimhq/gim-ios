import GIMClientKit
import GIMFeatures
import SwiftUI

/// The user's hubs (`hubList`): primary first, each with its state, whether this device is signed in there and the
/// Primary and Home badges. Hubs can be added, made primary and removed (after a confirmation, and a second one when
/// the hub hosts groups the user owns).
struct HubsScreen: View {
    let client: any GimClientAPI

    @State private var viewModel: HubsViewModel
    /// The Add Hub screen's model while it is shown; a new one each time, so no URL or error is left over.
    @State private var addHub: AddHubViewModel?

    init(client: any GimClientAPI) {
        self.client = client
        _viewModel = State(initialValue: HubsViewModel(client: client))
    }

    var body: some View {
        List {
            Section {
                ForEach(viewModel.hubs, id: \.hubId) { hub in
                    row(hub)
                }
            } footer: {
                if let error = viewModel.errorMessage {
                    Text(error).foregroundStyle(.red)
                } else {
                    Text(
                        "Messages go through your main server first. Your other servers keep a copy and take over when it is down.",
                        tableName: "Hubs", bundle: .module)
                }
            }
        }
        .accessibilityIdentifier("hubs.list")
        .overlay {
            if viewModel.hubs.isEmpty && viewModel.isLoading {
                ProgressView()
            }
        }
        .task { viewModel.start() }
        .navigationTitle(Text("Servers", tableName: "Hubs", bundle: .module))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    addHub = AddHubViewModel(client: client)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(Text("Add server", tableName: "Hubs", bundle: .module))
                .accessibilityIdentifier("hubs.add")
            }
        }
        .navigationDestination(isPresented: addHubPresented) {
            if let addHub {
                AddHubScreen(viewModel: addHub).id(ObjectIdentifier(addHub))
            }
        }
        .confirmationDialog(
            Text("Remove this server?", tableName: "Hubs", bundle: .module), isPresented: removalDialogPresented,
            titleVisibility: .visible, presenting: viewModel.pendingRemoval
        ) { hub in
            Button(String(localized: "Remove", table: "Common", bundle: .module), role: .destructive) {
                Task { await viewModel.confirmRemoval(of: hub) }
            }
        } message: { hub in
            Text(
                "\(HubsViewModel.address(of: hub)) will no longer receive or keep your messages.",
                tableName: "Hubs", bundle: .module)
        }
        .alert(
            Text("Remove server?", tableName: "Hubs", bundle: .module), isPresented: ownedGroupsAlertPresented,
            presenting: viewModel.ownedGroupsWarning
        ) { warning in
            Button(String(localized: "Remove anyway", table: "Hubs", bundle: .module), role: .destructive) {
                Task { await viewModel.confirmOwnedGroupsRemoval(warning) }
            }
            Button(String(localized: "Cancel", table: "Common", bundle: .module), role: .cancel) {}
        } message: { warning in
            Text(warning.message)
        }
        .alert(
            viewModel.notice?.title ?? "", isPresented: noticePresented, presenting: viewModel.notice
        ) { _ in
            Button(String(localized: "OK", table: "Common", bundle: .module)) {}
        } message: { notice in
            Text(notice.message)
        }
    }

    private func row(_ hub: HubInfo) -> some View {
        let key = HubsViewModel.address(of: hub)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(key).lineLimit(1).truncationMode(.middle)
                if hub.isPrimary {
                    HubBadge(text: String(localized: "Main", table: "Hubs", bundle: .module))
                        .accessibilityIdentifier("hubs.badge.primary")
                }
                if hub.isHome {
                    HubBadge(text: String(localized: "Home", table: "Hubs", bundle: .module))
                        .accessibilityIdentifier("hubs.badge.home")
                }
            }
            HStack(spacing: 12) {
                Text(HubsViewModel.stateText(hub.state))
                    .accessibilityIdentifier("hubs.state.\(key)")
                if hub.signedIn {
                    Label(
                        String(localized: "Signed in", table: "Hubs", bundle: .module), systemImage: "checkmark.circle"
                    )
                        .accessibilityIdentifier("hubs.signedIn.\(key)")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            if viewModel.busyHubId == hub.hubId {
                ProgressView()
            } else if hub.state != .removed {
                HStack(spacing: 20) {
                    if !hub.isPrimary {
                        Button(String(localized: "Make main", table: "Hubs", bundle: .module)) {
                            Task { await viewModel.setPrimary(hubId: hub.hubId) }
                        }
                        .disabled(!viewModel.canSetPrimary(hub))
                        .accessibilityIdentifier("hubs.setPrimary.\(key)")
                    }
                    Button(String(localized: "Remove", table: "Common", bundle: .module), role: .destructive) {
                        viewModel.requestRemoval(hub)
                    }
                    .disabled(!viewModel.canRemove(hub))
                    .accessibilityIdentifier("hubs.remove.\(key)")
                }
                .buttonStyle(.borderless)
                .font(.subheadline)
            }
        }
        .padding(.vertical, 2)
        .foregroundStyle(hub.state == .removed ? .secondary : .primary)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hubs.row.\(key)")
    }

    private var addHubPresented: Binding<Bool> {
        Binding(get: { addHub != nil }, set: { if !$0 { addHub = nil } })
    }

    private var removalDialogPresented: Binding<Bool> {
        Binding(get: { viewModel.pendingRemoval != nil }, set: { if !$0 { viewModel.cancelRemoval() } })
    }

    private var ownedGroupsAlertPresented: Binding<Bool> {
        Binding(
            get: { viewModel.ownedGroupsWarning != nil }, set: { if !$0 { viewModel.cancelOwnedGroupsRemoval() } })
    }

    private var noticePresented: Binding<Bool> {
        Binding(get: { viewModel.notice != nil }, set: { if !$0 { viewModel.dismissNotice() } })
    }
}

/// A small capsule label next to a hub's address.
private struct HubBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.15), in: Capsule())
            .foregroundStyle(Color.accentColor)
    }
}
