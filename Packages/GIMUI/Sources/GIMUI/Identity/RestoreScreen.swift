import GIMFeatures
import SwiftUI

/// Restores the user on this device from the recovery kit, or from the user id and the recovery code typed
/// separately (`restoreFromRecovery`), then tells the user that chats are not rejoined automatically before signing
/// in.
struct RestoreScreen: View {
    let context: OnboardingContext

    @State private var viewModel: RestoreViewModel
    @FocusState private var focusedField: Field?

    private enum Field {
        case kit
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
                TextField(
                    String(localized: "Paste your recovery kit", table: "Onboarding", bundle: .module),
                    text: $viewModel.kitText, axis: .vertical
                )
                .lineLimit(3...8)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .kit)
                .accessibilityIdentifier("restore.kit")
                ValidationMessage(text: viewModel.kitError)
            } header: {
                Text("Paste your recovery kit", tableName: "Onboarding", bundle: .module)
            } footer: {
                Text(
                    "Paste all of it. We find your Account ID and recovery key in it.", tableName: "Onboarding",
                    bundle: .module)
            }

            if viewModel.showsFields {
                Section {
                    TextField(
                        String(localized: "Account ID", table: "Onboarding", bundle: .module), text: $viewModel.userId
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .userId)
                    .accessibilityIdentifier("restore.userId")
                    .submitLabel(.next)
                    .onSubmit { focusedField = .code }
                    ValidationMessage(text: viewModel.userIdError)
                    TextField(
                        String(localized: "Recovery key", table: "Onboarding", bundle: .module),
                        text: $viewModel.recoveryCode, axis: .vertical
                    )
                    .font(.body.monospaced())
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .code)
                    .accessibilityIdentifier("restore.code")
                    ValidationMessage(text: viewModel.recoveryCodeError)
                } header: {
                    Text("Account ID and recovery key", tableName: "Onboarding", bundle: .module)
                } footer: {
                    Text(
                        "Account IDs start with u. Recovery keys have 39 characters; dashes and spaces are fine.",
                        tableName: "Onboarding", bundle: .module)
                }
            } else {
                Section {
                    Button {
                        viewModel.enterSeparately()
                    } label: {
                        Text("Enter them separately", tableName: "Onboarding", bundle: .module)
                            .font(.footnote)
                    }
                    .accessibilityIdentifier("restore.separate")
                }
                .listRowBackground(Color.clear)
            }

            Section {
                Toggle(isOn: $viewModel.revokeOthers) {
                    Text("Remove all other devices", tableName: "Onboarding", bundle: .module)
                }
                .accessibilityIdentifier("restore.revokeOthers")
            } footer: {
                Text(
                    "They get signed out. Do this if a device was lost or stolen.", tableName: "Onboarding",
                    bundle: .module)
            }

            Section {
                Button(action: submit) {
                    HStack {
                        Spacer()
                        if viewModel.isSubmitting {
                            ProgressView()
                        } else {
                            Text("Restore account", tableName: "Onboarding", bundle: .module).bold()
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
        .navigationTitle(Text("Restore your account", tableName: "Onboarding", bundle: .module))
        .onAppear { focusedField = .kit }
        .alert(
            Text("Account restored", tableName: "Onboarding", bundle: .module),
            isPresented: .constant(viewModel.showsRejoinNotice)
        ) {
            Button {
                viewModel.finish()
            } label: {
                Text("Continue", tableName: "Onboarding", bundle: .module)
            }
        } message: {
            Text(
                "Old chats don't come back. Ask friends to add you to groups again.", tableName: "Onboarding",
                bundle: .module)
        }
    }

    private func submit() {
        focusedField = nil
        Task { await viewModel.submit() }
    }
}
