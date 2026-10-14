import GIMClientKit
import SwiftUI

/// Top-level view: launch progress, onboarding, or the signed-in navigation stack.
public struct RootView: View {
    private let model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        Group {
            switch model.phase {
            case .launching:
                LaunchView(error: model.launchError) {
                    Task { await model.start() }
                }
            case .onboarding:
                if let onboarding = model.onboarding {
                    OnboardingScreen(viewModel: onboarding)
                }
            case .ready(let client):
                SignedInView(client: client, session: model.session) {
                    await model.signOut()
                }
            }
        }
        .task { await model.start() }
    }
}

private struct LaunchView: View {
    let error: String?
    let retry: () -> Void

    var body: some View {
        if let error {
            ContentUnavailableView {
                Label("Can't Start", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Try Again", action: retry)
                    .buttonStyle(.borderedProminent)
            }
        } else {
            ProgressView()
        }
    }
}

private struct SignedInView: View {
    let client: any GimClientAPI
    let session: Session?
    let signOut: () async -> String?

    @State private var path: [ChatId] = []
    @State private var showsSettings = false

    var body: some View {
        NavigationStack(path: $path) {
            ChatListScreen(client: client, onOpen: { path.append($0) }, onOpenSettings: { showsSettings = true })
                .navigationDestination(for: ChatId.self) { chatId in
                    ChatScreen(client: client, chatId: chatId)
                }
        }
        .sheet(isPresented: $showsSettings) {
            SettingsSheet(session: session, signOut: signOut)
        }
    }
}
