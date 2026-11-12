import GIMClientKit
import GIMFeatures
import SwiftUI

/// Opens a direct chat with someone by Account ID, scanned from their QR code or pasted, or the note to self; links to
/// group creation.
/// Shown inside a navigation stack.
public struct NewChatScreen: View {
    private let client: any GimClientAPI
    private let onOpen: (String) -> Void

    @State private var viewModel: NewChatViewModel
    @State private var isScanning = false
    @State private var scanError: String?
    @State private var accountId = ""
    @State private var accountIdError: String?
    @State private var noteError: String?
    @Environment(\.dismiss) private var dismiss

    /// - Parameter onOpen: called with the direct or group chat that was created.
    public init(client: any GimClientAPI, onOpen: @escaping (String) -> Void) {
        self.client = client
        self.onOpen = onOpen
        _viewModel = State(initialValue: NewChatViewModel(client: client))
    }

    public var body: some View {
        List {
            Section {
                NavigationLink {
                    NewGroupScreen(client: client, onCreated: onOpen)
                } label: {
                    Label {
                        Text("New group", tableName: "Contacts", bundle: .module)
                    } icon: {
                        Image(systemName: "person.3")
                    }
                }
                .accessibilityIdentifier("newChat.newGroup")
                Button {
                    scanError = nil
                    isScanning = true
                } label: {
                    Label {
                        Text("Scan QR code", tableName: "Contacts", bundle: .module)
                    } icon: {
                        Image(systemName: "qrcode.viewfinder")
                    }
                }
                .accessibilityIdentifier("newChat.scan")
                Button {
                    noteError = nil
                    Task {
                        if let chatId = await viewModel.startNoteToSelf() {
                            onOpen(chatId)
                        } else {
                            noteError = viewModel.startError
                        }
                    }
                } label: {
                    Label {
                        Text("Note to self", tableName: "Contacts", bundle: .module)
                    } icon: {
                        Image(systemName: "note.text")
                    }
                }
                .disabled(viewModel.isStarting)
                .accessibilityIdentifier("newChat.noteToSelf")
            } footer: {
                if let noteError {
                    Text(noteError).foregroundStyle(.red)
                }
            }
            Section {
                HStack {
                    TextField(text: $accountId) {
                        Text("Account ID", tableName: "Contacts", bundle: .module)
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .onSubmit(startChatWithAccountId)
                    .accessibilityIdentifier("newChat.accountId")
                    if viewModel.isStarting && !isScanning {
                        ProgressView()
                    } else {
                        Button(
                            String(localized: "Start chat", table: "Contacts", bundle: .module),
                            action: startChatWithAccountId
                        )
                        .disabled(accountId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("newChat.start")
                    }
                }
            } footer: {
                if let accountIdError {
                    Text(accountIdError)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("newChat.error")
                } else {
                    Text(
                        "Paste your friend's Account ID. They find it, and their QR code, in Settings.",
                        tableName: "Contacts", bundle: .module)
                }
            }
        }
        .navigationTitle(Text("New chat", tableName: "Contacts", bundle: .module))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isScanning) {
            ScanAccountIDScreen(error: $scanError, isWorking: viewModel.isStarting, onScanned: startChat(scanned:))
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "Cancel", table: "Common", bundle: .module)) { dismiss() }
            }
        }
    }

    private func startChat(scanned text: String) {
        guard !viewModel.isStarting else { return }
        scanError = nil
        Task {
            switch await viewModel.startChat(scanned: text) {
            case .started(let chatId):
                isScanning = false
                onOpen(chatId)
            case .noUserId:
                scanError = Self.notAnAccountId
            case .failed(let message):
                scanError = message
            }
        }
    }

    private func startChatWithAccountId() {
        guard !viewModel.isStarting, !accountId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        accountIdError = nil
        Task {
            switch await viewModel.startChat(scanned: accountId) {
            case .started(let chatId):
                onOpen(chatId)
            case .noUserId:
                accountIdError = Self.notAnAccountId
            case .failed(let message):
                accountIdError = message
            }
        }
    }

    private static var notAnAccountId: String {
        String(localized: "This code is not a gim Account ID.", table: "Contacts", bundle: .module)
    }
}

/// Avatar, name and short Account ID of one user.
struct UserRow: View {
    let user: UserProfile
    var detail: String?

    var body: some View {
        let name = UserLabel.name(for: user)
        HStack(spacing: 12) {
            AvatarView(id: user.userId, name: name, avatarPath: nil, size: 40)
            VStack(alignment: .leading) {
                Text(name).foregroundStyle(.primary)
                Text(detail ?? UserLabel.detail(for: user))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack {
        NewChatScreen(client: FakeGimClient.demo()) { _ in }
    }
}
