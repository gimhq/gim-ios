import GIMClientKit
import GIMFeatures
import SwiftUI

/// Top-level view: launch progress, onboarding, or the signed-in navigation stack.
public struct RootView: View {
    private let model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppearanceSetting.defaultsKey) private var appearanceRaw = AppearanceSetting.system.rawValue
    #if DEBUG
        @State private var debugPush = DebugPushProcessor()
    #endif

    public init(model: AppModel) {
        self.model = model
    }

    private var appearance: AppearanceSetting {
        AppearanceSetting(rawValue: appearanceRaw) ?? .system
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
                SignedInView(
                    client: client, session: model.session,
                    refreshSession: { await model.refreshSession() }, signOut: { await model.signOut() })
            }
        }
        .preferredColorScheme(appearance.colorScheme)
        .task { await model.start() }
        .onChange(of: scenePhase, initial: true) { _, newPhase in
            Task { await model.scenePhaseChanged(newPhase) }
        }
        #if DEBUG
            .onOpenURL { url in
                Task { await debugPush.handle(url, model: model) }
            }
            .overlay(alignment: .bottom) {
                if model.isSyncHeld {
                    Text(verbatim: "Sync held").font(.caption2).accessibilityIdentifier("debug.sync.held")
                }
            }
            .sheet(
                isPresented: Binding(
                    get: { debugPush.presentation != nil }, set: { if !$0 { debugPush.presentation = nil } })
            ) {
                if let presentation = debugPush.presentation {
                    DebugPushSheet(presentation: presentation)
                }
            }
        #endif
    }
}

private struct LaunchView: View {
    let error: String?
    let retry: () -> Void

    var body: some View {
        if let error {
            ContentUnavailableView {
                Label {
                    Text("Couldn't start", tableName: "Common", bundle: .module)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
            } description: {
                Text(error)
            } actions: {
                Button(action: retry) { Text("Try again", tableName: "Common", bundle: .module) }
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
    let refreshSession: @MainActor () async -> Void
    let signOut: () async -> String?

    @State private var path: [String] = []
    @State private var drafts = ComposerDrafts()
    @State private var showsSettings = false

    init(
        client: any GimClientAPI, session: Session?,
        refreshSession: @escaping @MainActor () async -> Void, signOut: @escaping () async -> String?
    ) {
        self.client = client
        self.session = session
        self.refreshSession = refreshSession
        self.signOut = signOut
    }

    var body: some View {
        NavigationStack(path: $path) {
            ChatListScreen(
                client: client, session: session, onOpen: { path.append($0) },
                onOpenSettings: { showsSettings = true }
            )
            .navigationDestination(for: String.self) { chatId in
                ConversationScreen(client: client, chatId: chatId, drafts: drafts)
            }
        }
        .fullScreenCover(isPresented: $showsSettings) {
            NavigationStack {
                SettingsScreen(client: client, session: session, refreshSession: refreshSession, signOut: signOut)
            }
        }
    }
}
