import GIMClientKit
import GIMFeatures
import GIMPlatform
import PhotosUI
import SwiftUI
import UIKit

/// The root of the Settings stack: profile, devices, privacy, notifications, appearance, language, servers, keep
/// server, help, sign-out and account deletion.
struct SettingsScreen: View {
    let client: any GimClientAPI
    let session: Session?
    /// Re-reads the session after the name changed.
    let refreshSession: @MainActor () async -> Void
    let signOut: () async -> String?
    let deleteAccount: () async -> String?
    let makeKeepServer: @MainActor () -> KeepServerViewModel

    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppearanceSetting.defaultsKey) private var appearanceRaw = AppearanceSetting.system.rawValue
    @State private var profile: ProfileViewModel
    @State private var profilePhoto: ProfilePhotoViewModel
    @State private var showsPhotoPicker = false
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var isPreparingPhoto = false
    @State private var confirmsRemovePhoto = false
    @State private var isSigningOut = false
    @State private var confirmsSignOut = false
    @State private var errorMessage: String?
    @State private var copiedUserId = false
    @State private var recoveryKeyRotation: RecoveryKeyRotationViewModel

    init(
        client: any GimClientAPI, session: Session?, refreshSession: @escaping @MainActor () async -> Void,
        signOut: @escaping () async -> String?, deleteAccount: @escaping () async -> String?,
        makeKeepServer: @escaping @MainActor () -> KeepServerViewModel
    ) {
        self.client = client
        self.session = session
        self.refreshSession = refreshSession
        self.signOut = signOut
        self.deleteAccount = deleteAccount
        self.makeKeepServer = makeKeepServer
        _profile = State(initialValue: ProfileViewModel(client: client, onChanged: refreshSession))
        _profilePhoto = State(
            initialValue: ProfilePhotoViewModel(
                client: client, cacheDirectory: URL.cachesDirectory.appendingPathComponent("profile-photo"),
                onChanged: refreshSession))
        _recoveryKeyRotation = State(
            initialValue: RecoveryKeyRotationViewModel(
                client: client, userId: session?.userId ?? "", recoveryKit: CoreRecoveryKitFunctions()))
    }

    var body: some View {
        Form {
            if let session {
                profileSection(session)
                accountSection
                privacySection
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
                NavigationLink {
                    KeepServerScreen(model: makeKeepServer())
                } label: {
                    Text("Keep server", tableName: "Settings", bundle: .module)
                }
                .accessibilityIdentifier("settings.keepServer")
            } header: {
                Text("Advanced", tableName: "Settings", bundle: .module)
            } footer: {
                Text(
                    "The Keep server backs up your privacy settings and receives the reports you send. Your backup is encrypted.",
                    tableName: "Settings", bundle: .module)
            }
            helpSection
            signOutSection
            if session != nil {
                deleteAccountSection
            }
        }
        .navigationTitle(Text("Settings", tableName: "Settings", bundle: .module))
        .navigationBarTitleDisplayMode(.inline)
        .task { await profilePhoto.load() }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    dismiss()
                } label: {
                    Text("Done", tableName: "Common", bundle: .module)
                }
            }
        }
        .navigationDestination(isPresented: showsNewRecoveryKit) {
            if let kit = recoveryKeyRotation.kit {
                RecoveryKitScreen(viewModel: kit)
            }
        }
        .alert(
            Text("Create a new recovery key?", tableName: "Settings", bundle: .module),
            isPresented: confirmsNewRecoveryKey
        ) {
            Button {
                Task { await recoveryKeyRotation.rotate() }
            } label: {
                Text("Create new key", tableName: "Settings", bundle: .module)
            }
            .accessibilityIdentifier("settings.newRecoveryKey.create")
            Button(role: .cancel) {
                recoveryKeyRotation.cancel()
            } label: {
                Text("Cancel", tableName: "Common", bundle: .module)
            }
        } message: {
            Text(
                "Your current recovery key stops working. The new recovery kit replaces the old one, so save it again.",
                tableName: "Settings", bundle: .module)
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
                    AvatarView(
                        id: session.userId, name: session.displayName, avatarPath: profilePhoto.photoPath, size: 56)
                    Text(session.displayName).font(.headline)
                }
            }
            .accessibilityIdentifier("settings.profile")
            profilePhotoRow
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
            if let error = profile.errorMessage ?? profilePhoto.errorMessage {
                Text(error).foregroundStyle(.red)
            }
        }
    }

    private var profilePhotoRow: some View {
        Menu {
            Button {
                showsPhotoPicker = true
            } label: {
                Text("Choose photo", tableName: "Settings", bundle: .module)
            }
            .accessibilityIdentifier("settings.profilePhoto.choose")
            if profilePhoto.hasPhoto {
                Button(role: .destructive) {
                    confirmsRemovePhoto = true
                } label: {
                    Text("Remove photo", tableName: "Settings", bundle: .module)
                }
                .accessibilityIdentifier("settings.profilePhoto.remove")
            }
        } label: {
            HStack {
                Text("Profile photo", tableName: "Settings", bundle: .module)
                Spacer()
                if profilePhoto.isSaving || isPreparingPhoto { ProgressView() }
            }
        }
        .foregroundStyle(.primary)
        .disabled(profilePhoto.isSaving || isPreparingPhoto)
        .accessibilityIdentifier("settings.profilePhoto")
        .photosPicker(isPresented: $showsPhotoPicker, selection: $pickedPhoto, matching: .images)
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            pickedPhoto = nil
            Task { await setPhoto(from: item) }
        }
        .confirmationDialog(
            Text("Remove your profile photo?", tableName: "Settings", bundle: .module),
            isPresented: $confirmsRemovePhoto, titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                Task { await profilePhoto.removePhoto() }
            } label: {
                Text("Remove", tableName: "Common", bundle: .module)
            }
        } message: {
            Text("People in your chats will see your initials instead.", tableName: "Settings", bundle: .module)
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
            Button {
                recoveryKeyRotation.start()
            } label: {
                HStack {
                    Text("Create a new recovery key", tableName: "Settings", bundle: .module)
                    Spacer()
                    if recoveryKeyRotation.state == .rotating { ProgressView() }
                }
            }
            .foregroundStyle(.primary)
            .disabled(recoveryKeyRotation.state == .rotating)
            .accessibilityIdentifier("settings.newRecoveryKey")
        } header: {
            Text("Account and devices", tableName: "Settings", bundle: .module)
        } footer: {
            if case .failed(let message) = recoveryKeyRotation.state {
                Text(message).foregroundStyle(.red)
            } else if recoveryKeyRotation.hasUnsyncedServers {
                Text("Some servers couldn't be updated yet. Try again later.", tableName: "Settings", bundle: .module)
            }
        }
    }

    private var confirmsNewRecoveryKey: Binding<Bool> {
        Binding(
            get: { recoveryKeyRotation.state == .confirming },
            set: { presented in if !presented { recoveryKeyRotation.cancel() } })
    }

    /// The new kit stays on screen until the user confirmed its ending; `RecoveryKitScreen` hides the back button.
    private var showsNewRecoveryKit: Binding<Bool> {
        Binding(get: { recoveryKeyRotation.kit != nil }, set: { _ in })
    }

    private var privacySection: some View {
        Section {
            NavigationLink {
                PrivacyScreen(client: client)
            } label: {
                Text("Privacy settings", tableName: "Settings", bundle: .module)
            }
            .accessibilityIdentifier("settings.privacy")
        } header: {
            Text("Privacy", tableName: "Settings", bundle: .module)
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

    private var deleteAccountSection: some View {
        Section {
            NavigationLink {
                DeleteAccountScreen { await performDeleteAccount() }
            } label: {
                Text("Delete account", tableName: "Settings", bundle: .module).foregroundStyle(.red)
            }
            .accessibilityIdentifier("settings.deleteAccount")
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

    /// Prepares the picked image off the main thread and sets it as the profile photo.
    private func setPhoto(from item: PhotosPickerItem) async {
        isPreparingPhoto = true
        defer { isPreparingPhoto = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw MediaPreparationError.unreadable
            }
            let url = try await Task.detached(priority: .userInitiated) { try ProfilePhotoEncoder.encode(data) }.value
            await profilePhoto.setPhoto(filePath: url.path)
            TemporaryAttachment.remove(url)
        } catch {
            profilePhoto.photoFailed(error)
        }
    }

    private func performSignOut() async {
        isSigningOut = true
        errorMessage = await signOut()
        isSigningOut = false
        if errorMessage == nil { dismiss() }
    }

    private func performDeleteAccount() async -> String? {
        let error = await deleteAccount()
        if error == nil { dismiss() }
        return error
    }
}
