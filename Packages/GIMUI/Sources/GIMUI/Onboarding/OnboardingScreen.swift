import GIMClientKit
import GIMFeatures
import SwiftUI

/// Registration form: server address, handle and display name.
public struct OnboardingScreen: View {
    @Bindable private var viewModel: OnboardingViewModel
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case serverUrl
        case handle
        case displayName
    }

    public init(viewModel: OnboardingViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://gim.example.eu", text: $viewModel.serverUrl)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .serverUrl)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .handle }
                    ValidationMessage(text: viewModel.serverUrlError)
                } header: {
                    Text("Server")
                } footer: {
                    Text("The address of your gim server, for example a machine on your local network.")
                }

                Section("Profile") {
                    TextField("Handle", text: $viewModel.handle)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .handle)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .displayName }
                    ValidationMessage(text: viewModel.handleError)

                    TextField("Display name", text: $viewModel.displayName)
                        .textContentType(.name)
                        .focused($focusedField, equals: .displayName)
                        .submitLabel(.go)
                        .onSubmit(submit)
                    ValidationMessage(text: viewModel.displayNameError)
                }

                Section {
                    Button(action: submit) {
                        HStack {
                            Spacer()
                            if viewModel.isSubmitting {
                                ProgressView()
                            } else {
                                Text("Create Account").bold()
                            }
                            Spacer()
                        }
                    }
                    .disabled(viewModel.isSubmitting)
                } footer: {
                    if let error = viewModel.errorMessage {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .disabled(viewModel.isSubmitting)
            .navigationTitle("Welcome to GIM")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
        }
    }

    private func submit() {
        focusedField = nil
        Task { await viewModel.submit() }
    }
}

private struct ValidationMessage: View {
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
