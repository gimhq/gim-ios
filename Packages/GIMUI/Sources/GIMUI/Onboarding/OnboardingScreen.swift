import GIMClientKit
import GIMFeatures
import GIMPlatform
import SwiftUI

/// Onboarding: the server address and the choice between creating, linking and restoring an identity; after the
/// identity was created, the recovery code and handle steps.
public struct OnboardingScreen: View {
    @Bindable private var viewModel: OnboardingViewModel
    @FocusState private var focusesServerUrl: Bool

    public init(viewModel: OnboardingViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        switch viewModel.stage {
        case .recoveryCode(let recoveryCode):
            NavigationStack { RecoveryCodeScreen(viewModel: recoveryCode) }
        case .claimHandle(let claimHandle):
            NavigationStack { ClaimHandleScreen(viewModel: claimHandle, allowsSkip: true) }
        case nil:
            start
        }
    }

    private var start: some View {
        NavigationStack(path: $viewModel.path) {
            Form {
                if viewModel.showsLocalStateResetNotice {
                    Section {
                        Label("Local history on this device was reset.", systemImage: "info.circle")
                        Button("Dismiss") { viewModel.dismissLocalStateResetNotice() }
                    }
                    .accessibilityIdentifier("onboarding.resetNotice")
                }

                Section {
                    TextField("https://gim.example.eu", text: $viewModel.serverUrl)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusesServerUrl)
                        .accessibilityIdentifier("onboarding.serverUrl")
                        .submitLabel(.done)
                    ValidationMessage(text: viewModel.serverUrlError)
                } header: {
                    Text("Server")
                } footer: {
                    Text("The address of your gim server, for example a machine on your local network.")
                }

                Section {
                    Button {
                        choose(.createIdentity)
                    } label: {
                        HStack {
                            Spacer()
                            Text("Create New Identity").bold()
                            Spacer()
                        }
                    }
                    .accessibilityIdentifier("onboarding.create")
                    Button("Link to an Existing Device") { choose(.linkDevice) }
                        .accessibilityIdentifier("onboarding.link")
                    Button("Restore from Recovery Code") { choose(.restore) }
                        .accessibilityIdentifier("onboarding.restore")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Welcome to GIM")
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
            factory: CoreGimClientFactory(), hooks: AppPlatformHooks(dataDirectory: NSTemporaryDirectory())
        ) { _ in })
}
