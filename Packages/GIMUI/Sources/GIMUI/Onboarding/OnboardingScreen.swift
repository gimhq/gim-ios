import GIMClientKit
import GIMFeatures
import GIMPlatform
import SwiftUI

/// Onboarding: a short intro, the choice between creating, linking and restoring an account, and the server
/// address; after the identity was created, the recovery kit step.
public struct OnboardingScreen: View {
    @Bindable private var viewModel: OnboardingViewModel
    @FocusState private var focusesServerUrl: Bool

    public init(viewModel: OnboardingViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        switch viewModel.stage {
        case .recoveryKit(let recoveryKit):
            NavigationStack { RecoveryKitScreen(viewModel: recoveryKit) }
        case .claimHandle, nil:
            start
        }
    }

    private var start: some View {
        NavigationStack(path: $viewModel.path) {
            Form {
                if viewModel.showsLocalStateResetNotice {
                    Section {
                        Label {
                            Text("Chat history on this device was reset.", tableName: "Onboarding", bundle: .module)
                        } icon: {
                            Image(systemName: "info.circle")
                        }
                        Button {
                            viewModel.dismissLocalStateResetNotice()
                        } label: {
                            Text("Dismiss", tableName: "Onboarding", bundle: .module)
                        }
                    }
                    .accessibilityIdentifier("onboarding.resetNotice")
                }

                Section {
                    Image("GimGlyph", bundle: .module)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64, height: 64)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                        .accessibilityHidden(true)
                        .listRowSeparator(.hidden)
                    TabView {
                        ForEach(IntroPage.all) { page in
                            VStack(spacing: 12) {
                                Text(LocalizedStringKey(page.title), tableName: "Explainer", bundle: .module)
                                    .font(.title2.bold())
                                    .multilineTextAlignment(.center)
                                Text(LocalizedStringKey(page.body), tableName: "Explainer", bundle: .module)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.horizontal, 24)
                            // Keeps the page dots clear of the text.
                            .padding(.bottom, 32)
                        }
                    }
                    .tabViewStyle(.page)
                    .indexViewStyle(.page(backgroundDisplayMode: .always))
                    .frame(height: 260)
                    .accessibilityIdentifier("onboarding.intro")
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                Section {
                    Button {
                        choose(.createIdentity)
                    } label: {
                        HStack {
                            Spacer()
                            Text("Create account", tableName: "Onboarding", bundle: .module).bold()
                            Spacer()
                        }
                    }
                    .accessibilityIdentifier("onboarding.create")
                    Button {
                        choose(.linkDevice)
                    } label: {
                        Text("I already have an account", tableName: "Onboarding", bundle: .module)
                    }
                    .accessibilityIdentifier("onboarding.link")
                    Button {
                        choose(.restore)
                    } label: {
                        Text("Restore", tableName: "Onboarding", bundle: .module)
                    }
                    .accessibilityIdentifier("onboarding.restore")
                } footer: {
                    Text(
                        "Already using gim on another device? Link this one. Lost all your devices? Restore with your recovery kit.",
                        tableName: "Onboarding", bundle: .module)
                }

                if viewModel.showsServerField {
                    Section {
                        TextField(
                            String(localized: "https://", table: "Onboarding", bundle: .module),
                            text: $viewModel.serverUrl
                        )
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusesServerUrl)
                        .accessibilityIdentifier("onboarding.serverUrl")
                        .submitLabel(.done)
                        ValidationMessage(text: viewModel.serverUrlError)
                    } header: {
                        Text("Server", tableName: "Onboarding", bundle: .module)
                    } footer: {
                        Text("The server your account uses.", tableName: "Onboarding", bundle: .module)
                    }
                } else {
                    Section {
                        Button {
                            viewModel.revealServerField()
                        } label: {
                            Text("Use another server", tableName: "Onboarding", bundle: .module)
                                .font(.footnote)
                        }
                        .accessibilityIdentifier("onboarding.useAnotherServer")
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(Text("Welcome to gim", tableName: "Onboarding", bundle: .module))
            .navigationDestination(for: OnboardingRoute.self) { route in
                destination(route)
            }
        }
    }

    @ViewBuilder
    private func destination(_ route: OnboardingRoute) -> some View {
        switch route {
        case .createIdentity:
            if let createIdentity = viewModel.createIdentity {
                CreateIdentityScreen(viewModel: createIdentity)
            }
        case .linkDevice:
            if let context = viewModel.context {
                LinkThisDeviceScreen(context: context)
            }
        case .restore:
            if let context = viewModel.context {
                RestoreScreen(context: context)
            }
        }
    }

    private func choose(_ route: OnboardingRoute) {
        focusesServerUrl = false
        viewModel.choose(route)
    }
}

/// One page of the intro pager; `title` and `body` are keys of the Explainer table.
private struct IntroPage: Identifiable, Sendable {
    let id: String
    let title: String
    let body: String

    static let all = [
        IntroPage(
            id: "noPhoneNumber", title: "explainer_no_phone_number_title", body: "explainer_no_phone_number_body"),
        IntroPage(
            id: "onYourDevices", title: "explainer_on_your_devices_title", body: "explainer_on_your_devices_body"),
        IntroPage(
            id: "lockedMessages", title: "explainer_locked_messages_title", body: "explainer_locked_messages_body"),
    ]
}

struct ValidationMessage: View {
    let text: String?

    var body: some View {
        if let text {
            Text(text)
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }
}

#Preview {
    OnboardingScreen(
        viewModel: OnboardingViewModel(
            factory: CoreGimClientFactory(), hooks: AppPlatformHooks(dataDirectory: NSTemporaryDirectory()),
            recoveryKit: CoreRecoveryKitFunctions()
        ) { _ in })
}
