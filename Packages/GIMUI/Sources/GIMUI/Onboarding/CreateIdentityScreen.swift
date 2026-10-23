import GIMFeatures
import SwiftUI

/// First step of creating an identity: the display name.
struct CreateIdentityScreen: View {
    @Bindable var viewModel: CreateIdentityViewModel
    @FocusState private var focusesName: Bool

    var body: some View {
        Form {
            Section {
                TextField(
                    String(localized: "Your name", table: "Onboarding", bundle: .module), text: $viewModel.displayName
                )
                .textContentType(.name)
                .focused($focusesName)
                .accessibilityIdentifier("identity.displayName")
                .submitLabel(.go)
                .onSubmit(submit)
                ValidationMessage(text: viewModel.displayNameError)
            } footer: {
                Text(
                    "People see this name in your chats. You can change it later.", tableName: "Onboarding",
                    bundle: .module)
            }

            Section {
                Button(action: submit) {
                    HStack {
                        Spacer()
                        if viewModel.isSubmitting {
                            ProgressView()
                        } else {
                            Text("Create account", tableName: "Onboarding", bundle: .module).bold()
                        }
                        Spacer()
                    }
                }
                .disabled(viewModel.isSubmitting)
                .accessibilityIdentifier("identity.create")
            } footer: {
                if let error = viewModel.errorMessage {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .disabled(viewModel.isSubmitting)
        .navigationTitle(Text("What should people call you?", tableName: "Onboarding", bundle: .module))
        .onAppear { focusesName = true }
    }

    private func submit() {
        focusesName = false
        Task { await viewModel.submit() }
    }
}
