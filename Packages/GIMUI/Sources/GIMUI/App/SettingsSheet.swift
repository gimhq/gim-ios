import GIMClientKit
import SwiftUI

/// Shows the current session and lets the user sign out.
struct SettingsSheet: View {
    let session: Session?
    let signOut: () async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var isSigningOut = false
    @State private var confirmsSignOut = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                if let session {
                    Section {
                        HStack(spacing: 12) {
                            AvatarView(id: session.userId, name: session.displayName, avatarPath: nil, size: 48)
                            VStack(alignment: .leading) {
                                Text(session.displayName).font(.headline)
                                Text("@\(session.handle)").foregroundStyle(.secondary)
                            }
                        }
                    }
                    Section("Session") {
                        LabeledContent("Server", value: session.serverUrl)
                        LabeledContent("User ID", value: session.userId)
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
            .confirmationDialog("Sign out of this device?", isPresented: $confirmsSignOut, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) {
                    Task { await performSignOut() }
                }
            } message: {
                Text("Messages stored on this device will be removed.")
            }
        }
    }

    private func performSignOut() async {
        isSigningOut = true
        errorMessage = await signOut()
        isSigningOut = false
        if errorMessage == nil { dismiss() }
    }
}
