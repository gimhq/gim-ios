import GIMFeatures
import SwiftUI

/// Lets the user choose a handle others can find them by; used by onboarding (skippable) and Settings.
struct ClaimHandleScreen: View {
    @Bindable var viewModel: ClaimHandleViewModel
    let allowsSkip: Bool
    @FocusState private var focusesHandle: Bool

    var body: some View {
        Form {
            Section {
                TextField(String(localized: "Username", table: "Onboarding", bundle: .module), text: $viewModel.handle)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusesHandle)
                    .accessibilityIdentifier("handle.field")
                    .submitLabel(.go)
                    .onSubmit(claim)
                ValidationMessage(text: viewModel.handleError)
            } footer: {
                Text(
                    "Friends can find you with it. It's optional. You can add one later. 3 to 32 characters: a–z, 0–9, _ and .",
                    tableName: "Onboarding", bundle: .module)
            }

            Section {
                Button(action: claim) {
                    HStack {
                        Spacer()
                        if viewModel.isSubmitting {
                            ProgressView()
                        } else {
                            Text("Save username", tableName: "Onboarding", bundle: .module).bold()
                        }
                        Spacer()
                    }
                }
                .disabled(viewModel.isSubmitting)
                .accessibilityIdentifier("handle.claim")
            } footer: {
                if let error = viewModel.errorMessage {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .disabled(viewModel.isSubmitting)
        .navigationTitle(Text("Choose a username", tableName: "Onboarding", bundle: .module))
        .navigationBarBackButtonHidden(allowsSkip)
        .toolbar {
            if allowsSkip {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        focusesHandle = false
                        Task { await viewModel.skip() }
                    } label: {
                        Text("Skip for now", tableName: "Onboarding", bundle: .module)
                    }
                    .disabled(viewModel.isSubmitting)
                    .accessibilityIdentifier("handle.skip")
                }
            }
        }
    }

    private func claim() {
        focusesHandle = false
        Task { await viewModel.claim() }
    }
}
