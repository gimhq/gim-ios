import GIMClientKit
import GIMFeatures
import SwiftUI

/// Read receipts, typing indicators and the blocked people.
struct PrivacyScreen: View {
    let client: any GimClientAPI

    @State private var viewModel: PrivacyViewModel

    init(client: any GimClientAPI) {
        self.client = client
        _viewModel = State(initialValue: PrivacyViewModel(client: client))
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: readReceipts) {
                    Text("Read receipts", tableName: "Settings", bundle: .module)
                }
                .accessibilityIdentifier("settings.privacy.readReceipts")
            } footer: {
                Text(
                    "When this is off, others don't see when you've read their messages, and you don't see when they've read yours.",
                    tableName: "Settings", bundle: .module)
            }
            Section {
                Toggle(isOn: typingIndicators) {
                    Text("Typing indicators", tableName: "Settings", bundle: .module)
                }
                .accessibilityIdentifier("settings.privacy.typing")
            } footer: {
                Text(
                    "When this is off, others don't see when you're typing, and you don't see when they are.",
                    tableName: "Settings", bundle: .module)
            }
            Section {
                NavigationLink {
                    BlockedUsersScreen(client: client)
                } label: {
                    LabeledContent {
                        Text(viewModel.blockedCount, format: .number)
                    } label: {
                        Text("Blocked people", tableName: "Settings", bundle: .module)
                    }
                }
                .accessibilityIdentifier("settings.privacy.blocked")
            } footer: {
                if let error = viewModel.errorMessage {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(Text("Privacy", tableName: "Settings", bundle: .module))
        .navigationBarTitleDisplayMode(.inline)
        // Runs again when coming back from the blocked people, so the count follows unblocks.
        .task { await viewModel.load() }
    }

    private var readReceipts: Binding<Bool> {
        Binding(get: { viewModel.readReceipts }, set: { value in Task { await viewModel.setReadReceipts(value) } })
    }

    private var typingIndicators: Binding<Bool> {
        Binding(
            get: { viewModel.typingIndicators }, set: { value in Task { await viewModel.setTypingIndicators(value) } })
    }
}
