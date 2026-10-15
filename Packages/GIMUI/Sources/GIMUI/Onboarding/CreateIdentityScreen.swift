import GIMFeatures
import SwiftUI

/// First step of creating an identity: the display name.
struct CreateIdentityScreen: View {
    @Bindable var viewModel: CreateIdentityViewModel
    @FocusState private var focusesName: Bool

    var body: some View {
        Form {
            Section {
                TextField("Display name", text: $viewModel.displayName)
                    .textContentType(.name)
                    .focused($focusesName)
                    .accessibilityIdentifier("identity.displayName")
                    .submitLabel(.go)
                    .onSubmit(submit)
                ValidationMessage(text: viewModel.displayNameError)
            } footer: {
                Text("Shown to the people you chat with. You can change it later.")
            }

            Section {
                Button(action: submit) {
                    HStack {
                        Spacer()
                        if viewModel.isSubmitting {
                            ProgressView()
                        } else {
                            Text("Create Identity").bold()
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
        .navigationTitle("New Identity")
        .onAppear { focusesName = true }
    }

    private func submit() {
        focusesName = false
        Task { await viewModel.submit() }
    }
}
