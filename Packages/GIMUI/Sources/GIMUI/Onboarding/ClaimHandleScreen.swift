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
                TextField("Handle", text: $viewModel.handle)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusesHandle)
                    .accessibilityIdentifier("handle.field")
                    .submitLabel(.go)
                    .onSubmit(claim)
                ValidationMessage(text: viewModel.handleError)
            } footer: {
                Text("People can start a chat with you by your handle. 3 to 32 letters, digits, underscores or dots.")
            }

            Section {
                Button(action: claim) {
                    HStack {
                        Spacer()
                        if viewModel.isSubmitting {
                            ProgressView()
                        } else {
                            Text("Claim Handle").bold()
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
        .navigationTitle("Choose a Handle")
        .navigationBarBackButtonHidden(allowsSkip)
        .toolbar {
            if allowsSkip {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Skip") {
                        focusesHandle = false
                        Task { await viewModel.skip() }
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
