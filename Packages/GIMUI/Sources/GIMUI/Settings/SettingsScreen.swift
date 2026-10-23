import GIMClientKit
import GIMFeatures
import SwiftUI
import UIKit

/// The root of the Settings stack: profile, devices, notifications, appearance, language, servers, help and sign-out.
struct SettingsScreen: View {
    let client: any GimClientAPI
    let session: Session?
    /// Re-reads the session after the name or the handle changed.
    let refreshSession: @MainActor () async -> Void
    let signOut: () async -> String?

    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppearanceSetting.defaultsKey) private var appearanceRaw = AppearanceSetting.system.rawValue
    @State private var profile: ProfileViewModel
    @State private var isSigningOut = false
    @State private var confirmsSignOut = false
    @State private var errorMessage: String?
    @State private var claimHandle: ClaimHandleViewModel?
    @State private var showsClaimHandle = false
    @State private var showsHandleActions = false
    @State private var confirmsRemoveHandle = false
    @State private var copiedUserId = false

    init(
        client: any GimClientAPI, session: Session?, refreshSession: @escaping @MainActor () async -> Void,
        signOut: @escaping () async -> String?
    ) {
        self.client = client
        self.session = session
        self.refreshSession = refreshSession
        self.signOut = signOut
        _profile = State(initialValue: ProfileViewModel(client: client, onChanged: refreshSession))
    }

    var body: some View {
        Form {
            if let session {
                profileSection(session)
                accountSection
            }
            Section {
                Button {
                    open(UIApplication.openNotificationSettingsURLString)
                } label: {
                    Text("Notification settings", tableName: "Settings", bundle: .module)
                }
                .accessibilityIdentifier("settings.notifications")
            } header: {
                Text("Notifications", tableName: "Settings", bundle: .module)
            } footer: {
                Text("Opens the system settings for gim's notifications.", tableName: "Settings", bundle: .module)
            }
            Section {
                Picker(selection: $appearanceRaw) {
                    ForEach(AppearanceSetting.allCases, id: \.self) { setting in
                        Text(setting.title).tag(setting.rawValue)
                    }
                } label: {
                    Text("Theme", tableName: "Settings", bundle: .module)
                }
                .accessibilityIdentifier("settings.theme")
            } header: {
                Text("Appearance", tableName: "Settings", bundle: .module)
            }
            Section {
                Button {
                    open(UIApplication.openSettingsURLString)
                } label: {
                    LabeledContent {
                        Text(LanguageSetting.currentLanguageName())
                    } label: {
                        Text("Language", tableName: "Settings", bundle: .module)
                    }
                }
                .foregroundStyle(.primary)
                .accessibilityIdentifier("settings.language")
            } header: {
                Text("Language", tableName: "Settings", bundle: .module)
            } footer: {
                Text("Choose gim's language in the system settings.", tableName: "Settings", bundle: .module)
            }
            Section {
                NavigationLink {
                    HubsScreen(client: client)
                } label: {
                    Text("Servers", tableName: "Settings", bundle: .module)
                }
                .accessibilityIdentifier("settings.hubs")
            } header: {
                Text("Advanced", tableName: "Settings", bundle: .module)
            }
            helpSection
            signOutSection
        }
        .navigationTitle(Text("Settings", tableName: "Settings", bundle: .module))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    dismiss()
                } label: {
                    Text("Done", tableName: "Common", bundle: .module)
                }
            }
        }
        .navigationDestination(isPresented: $showsClaimHandle) {
            if let claimHandle {
                ClaimHandleScreen(viewModel: claimHandle, allowsSkip: false)
            }
        }
        .confirmationDialog(
            Text("Sign out of gim on this device?", tableName: "Settings", bundle: .module),
            isPresented: $confirmsSignOut, titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                Task { await performSignOut() }
            } label: {
                Text("Sign out", tableName: "Settings", bundle: .module)
            }
        } message: {
            Text(
                "You need your recovery kit and Account ID to come back. Messages kept on this device are removed.",
                tableName: "Settings", bundle: .module)
        }
    }

    private func profileSection(_ session: Session) -> some View {
        Section {
            NavigationLink {
                EditNameScreen(client: client, refreshSession: refreshSession)
            } label: {
                HStack(spacing: 12) {
                    AvatarView(id: session.userId, name: session.displayName, avatarPath: nil, size: 56)
                    VStack(alignment: .leading) {
                        Text(session.displayName).font(.headline)
                        if session.handle.isEmpty {
                            Text("No username yet", tableName: "Settings", bundle: .module)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(verbatim: "@" + session.handle).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .accessibilityIdentifier("settings.profile")
            usernameRow(session)
            Button {
                copy(session.userId)
            } label: {
                LabeledContent {
                    HStack {
                        Text(session.userId)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Image(systemName: copiedUserId ? "checkmark" : "doc.on.doc")
                    }
                } label: {
                    Text("Account ID", tableName: "Settings", bundle: .module)
                }
            }
            .foregroundStyle(.primary)
            .accessibilityLabel(session.userId)
            .accessibilityHint(Text("Copies your Account ID", tableName: "Settings", bundle: .module))
            .accessibilityIdentifier("settings.userId")
            NavigationLink {
                MyQRCodeScreen(userId: session.userId)
            } label: {
                Text("My QR code", tableName: "Settings", bundle: .module)
            }
            .accessibilityIdentifier("settings.qrCode")
        } header: {
            Text("Profile", tableName: "Settings", bundle: .module)
        } footer: {
            if let error = profile.errorMessage {
                Text(error).foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func usernameRow(_ session: Session) -> some View {
        if session.handle.isEmpty {
            Button {
                chooseHandle()
            } label: {
                HStack {
                    Text("Choose a username", tableName: "Settings", bundle: .module)
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(.primary)
            .accessibilityIdentifier("settings.username")
        } else {
            Button {
                showsHandleActions = true
            } label: {
                LabeledContent {
                    Text(verbatim: "@" + session.handle)
                } label: {
                    Text("Username", tableName: "Settings", bundle: .module)
                }
            }
            .foregroundStyle(.primary)
            .disabled(profile.isSaving)
            .accessibilityIdentifier("settings.username")
            .confirmationDialog(
                Text("Username", tableName: "Settings", bundle: .module), isPresented: $showsHandleActions
            ) {
                Button {
                    chooseHandle()
                } label: {
                    Text("Change username", tableName: "Settings", bundle: .module)
                }
                Button(role: .destructive) {
                    confirmsRemoveHandle = true
                } label: {
                    Text("Remove username", tableName: "Settings", bundle: .module)
                }
            }
            .confirmationDialog(
                Text("Remove your username?", tableName: "Settings", bundle: .module),
                isPresented: $confirmsRemoveHandle, titleVisibility: .visible
            ) {
                Button(role: .destructive) {
                    Task { await profile.removeHandle() }
                } label: {
                    Text("Remove", tableName: "Common", bundle: .module)
                }
            } message: {
                Text(
                    "Friends can no longer find you by it. Your Account ID still works.", tableName: "Settings",
                    bundle: .module)
            }
        }
    }

    private var accountSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("explainer_recovery_key_title", tableName: "Explainer", bundle: .module).font(.headline)
                Text("explainer_recovery_key_body", tableName: "Explainer", bundle: .module)
                    .foregroundStyle(.secondary)
            }
            NavigationLink {
                DevicesScreen(client: client)
            } label: {
                Text("Linked devices", tableName: "Settings", bundle: .module)
            }
            .accessibilityIdentifier("settings.devices")
            NavigationLink {
                ApproveLinkScreen(client: client)
            } label: {
                Text("Link a new device", tableName: "Settings", bundle: .module)
            }
            .accessibilityIdentifier("settings.linkDevice")
        } header: {
            Text("Account and devices", tableName: "Settings", bundle: .module)
        }
    }

    private var helpSection: some View {
        let about = AboutInfo.read(from: .main)
        return Section {
            NavigationLink {
                HowGimWorksScreen()
            } label: {
                Text("explainer_title", tableName: "Explainer", bundle: .module)
            }
            .accessibilityIdentifier("settings.howItWorks")
            LabeledContent {
                Text(about.appVersion)
            } label: {
                Text("App version", tableName: "Settings", bundle: .module)
            }
            if let coreVersion = about.coreVersion {
                LabeledContent {
                    Text(coreVersion)
                } label: {
                    Text("Core version", tableName: "Settings", bundle: .module)
                }
            }
        } header: {
            Text("Help and about", tableName: "Settings", bundle: .module)
        }
    }

    private var signOutSection: some View {
        Section {
            Button(role: .destructive) {
                confirmsSignOut = true
            } label: {
                HStack {
                    Text("Sign out", tableName: "Settings", bundle: .module)
                    Spacer()
                    if isSigningOut { ProgressView() }
                }
            }
            .disabled(isSigningOut)
            .accessibilityIdentifier("settings.signOut")
        } footer: {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
    }

    private func copy(_ userId: String) {
        UIPasteboard.general.string = userId
        copiedUserId = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copiedUserId = false
        }
    }

    private func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url)
    }

    private func chooseHandle() {
        claimHandle = ClaimHandleViewModel(client: client) {
            await refreshSession()
            showsClaimHandle = false
        }
        showsClaimHandle = true
    }

    private func performSignOut() async {
        isSigningOut = true
        errorMessage = await signOut()
        isSigningOut = false
        if errorMessage == nil { dismiss() }
    }
}
