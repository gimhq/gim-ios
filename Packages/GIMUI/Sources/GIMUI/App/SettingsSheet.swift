import GIMClientKit
import GIMFeatures
import SwiftUI
import UIKit

/// Shows the identity and session, links to device and hub management and lets the user sign out.
struct SettingsSheet: View {
    let client: any GimClientAPI
    let session: Session?
    let serverUrl: String?
    /// Re-reads the session after a handle was claimed.
    let refreshSession: @MainActor () async -> Void
    let signOut: () async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var isSigningOut = false
    @State private var confirmsSignOut = false
    @State private var errorMessage: String?
    @State private var claimHandle: ClaimHandleViewModel?
    @State private var showsClaimHandle = false

    var body: some View {
        NavigationStack {
            Form {
                if let session {
                    Section {
                        HStack(spacing: 12) {
                            AvatarView(id: session.userId, name: session.displayName, avatarPath: nil, size: 48)
                            VStack(alignment: .leading) {
                                Text(session.displayName).font(.headline)
                                if !session.handle.isEmpty {
                                    Text("@\(session.handle)").foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    Section("Identity") {
                        if let userId = client.userId() {
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
                            .accessibilityIdentifier("settings.userId")
                        }
                        if session.handle.isEmpty {
                            LabeledContent("Handle", value: "No handle")
                            Button("Choose a Handle") { chooseHandle() }
                        } else {
                            LabeledContent("Handle", value: "@\(session.handle)")
                        }
                    }
                    Section("Devices") {
                        NavigationLink("Devices") { DevicesScreen(client: client) }
                            .accessibilityIdentifier("settings.devices")
                        NavigationLink("Link a New Device") { ApproveLinkScreen(client: client) }
                            .accessibilityIdentifier("settings.linkDevice")
                    }
                    Section("Hubs") {
                        NavigationLink("Hubs") { HubsScreen(client: client) }
                            .accessibilityIdentifier("settings.hubs")
                    }
                    Section("Session") {
                        if let serverUrl {
                            LabeledContent("Server", value: serverUrl)
                        }
                        LabeledContent("Device ID", value: session.deviceId)
                    }
                }
                Section {
                    Button(role: .destructive) {
                        confirmsSignOut = true
                    } label: {
                        HStack {
                            Text("Sign Out")
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
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(isPresented: $showsClaimHandle) {
                if let claimHandle {
                    ClaimHandleScreen(viewModel: claimHandle, allowsSkip: false)
                }
            }
            .confirmationDialog("Sign out of this device?", isPresented: $confirmsSignOut, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) {
                    Task { await performSignOut() }
                }
            } message: {
                Text("Messages stored on this device will be removed.")
            }
        }
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
