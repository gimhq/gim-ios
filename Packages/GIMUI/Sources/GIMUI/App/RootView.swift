import GIMClientKit
import GIMFeatures
import SwiftUI

/// Top-level view: launch progress, onboarding, or the signed-in navigation stack.
public struct RootView: View {
    private let model: AppModel
    @Environment(\.scenePhase) private var scenePhase

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
                SignedInView(client: client, session: model.session, serverUrl: model.serverUrl) {
                    await model.signOut()
                }
            }
        }
        .task { await model.start() }
        .onChange(of: scenePhase, initial: true) { _, newPhase in
            Task { await model.scenePhaseChanged(newPhase) }
        }
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
    let serverUrl: String?
    let signOut: () async -> String?

    @State private var path: [String] = []
    @State private var drafts = ComposerDrafts()
    @State private var showsSettings = false

    var body: some View {
        NavigationStack(path: $path) {
            ChatListScreen(client: client, onOpen: { path.append($0) }, onOpenSettings: { showsSettings = true })
                .navigationDestination(for: String.self) { chatId in
                    ConversationScreen(client: client, chatId: chatId, drafts: drafts)
                }
        }
        .sheet(isPresented: $showsSettings) {
            SettingsSheet(session: session, serverUrl: serverUrl, signOut: signOut)
        }
    }
}
