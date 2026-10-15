import GIMFeatures
import SwiftUI

/// Restores the user on this device from the user id and the recovery code (`restoreFromRecovery`), then tells the
/// user that chats are not rejoined automatically before signing in.
struct RestoreScreen: View {
    let context: OnboardingContext

    @State private var viewModel: RestoreViewModel
    @FocusState private var focusedField: Field?

    private enum Field {
        case userId
        case code
    }

    init(context: OnboardingContext) {
        self.context = context
        _viewModel = State(initialValue: RestoreViewModel(context: context))
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        Form {
            Section {
                TextField("User ID", text: $viewModel.userId)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .userId)
                    .accessibilityIdentifier("restore.userId")
                    .submitLabel(.next)
                    .onSubmit { focusedField = .code }
                ValidationMessage(text: viewModel.userIdError)
                TextField("Recovery code", text: $viewModel.recoveryCode, axis: .vertical)
                    .font(.body.monospaced())
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .code)
                    .accessibilityIdentifier("restore.code")
                ValidationMessage(text: viewModel.recoveryCodeError)
            } footer: {
                Text(
                    "The user ID is shown in Settings on your other devices. The recovery code was shown once when you created your identity."
                )
            }

            Section {
                Toggle("Sign out my other devices", isOn: $viewModel.revokeOthers)
                    .accessibilityIdentifier("restore.revokeOthers")
            } footer: {
                Text("Recommended if you lost a device: it can no longer sign in or read new messages.")
            }

            Section {
                Button(action: submit) {
                    HStack {
                        Spacer()
                        if viewModel.isSubmitting {
                            ProgressView()
                        } else {
                            Text("Restore").bold()
                        }
                        Spacer()
                    }
                }
                .disabled(viewModel.isSubmitting)
                .accessibilityIdentifier("restore.submit")
            } footer: {
                if let error = viewModel.errorMessage {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .disabled(viewModel.isSubmitting)
        .navigationTitle("Restore")
        .onAppear { focusedField = .userId }
        .alert("Identity Restored", isPresented: .constant(viewModel.showsRejoinNotice)) {
            Button("Continue") { viewModel.finish() }
        } message: {
            Text("Your chats aren't rejoined automatically. Ask the other members to add this device again.")
        }
    }

    private func submit() {
        focusedField = nil
        Task { await viewModel.submit() }
    }
}
