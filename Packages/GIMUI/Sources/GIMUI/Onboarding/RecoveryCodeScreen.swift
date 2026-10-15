import GIMFeatures
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Shows the recovery code once, then asks for one of its groups.
struct RecoveryCodeScreen: View {
    @Bindable var viewModel: RecoveryCodeViewModel
    @FocusState private var focusesGroup: Bool

    var body: some View {
        Group {
            if viewModel.isConfirming {
                confirmation
            } else {
                code
            }
        }
        .navigationBarBackButtonHidden()
    }

    private var code: some View {
        Form {
            Section {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(Array(viewModel.groups.enumerated()), id: \.offset) { index, group in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(index + 1)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 18, alignment: .trailing)
                            Text(group).font(.system(.title3, design: .monospaced))
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.vertical, 8)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(viewModel.code ?? "")
                .accessibilityIdentifier("recovery.code")
                Button("Copy", systemImage: "doc.on.doc", action: copy)
                    .accessibilityIdentifier("recovery.copy")
            } footer: {
                Text(
                    "Write this code down and keep it somewhere safe. It is shown only once, and it is the only way "
                        + "to restore your identity if you lose all your devices.")
            }

            Section {
                Button {
                    viewModel.continueToConfirmation()
                } label: {
                    HStack {
                        Spacer()
                        Text("I Wrote It Down").bold()
                        Spacer()
                    }
                }
                .accessibilityIdentifier("recovery.continue")
            }
        }
        .navigationTitle("Recovery Code")
    }

    private var confirmation: some View {
        Form {
            Section {
                TextField("Group \(viewModel.confirmationGroupNumber)", text: $viewModel.confirmationInput)
                    .font(.system(.body, design: .monospaced))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($focusesGroup)
                    .accessibilityIdentifier("recovery.confirmField")
                    .submitLabel(.done)
                    .onSubmit(viewModel.confirm)
                ValidationMessage(text: viewModel.confirmationError)
            } header: {
                Text("Enter group \(viewModel.confirmationGroupNumber)")
            } footer: {
                Text(
                    "Type group \(viewModel.confirmationGroupNumber) of your recovery code to confirm you wrote it "
                        + "down.")
            }

            Section {
                Button {
                    viewModel.confirm()
                } label: {
                    HStack {
                        Spacer()
                        Text("Confirm").bold()
                        Spacer()
                    }
                }
                .accessibilityIdentifier("recovery.confirm")
            }
        }
        .navigationTitle("Confirm Code")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Show Code Again", systemImage: "chevron.backward") { viewModel.showCodeAgain() }
                    .labelStyle(.titleAndIcon)
            }
        }
        .onAppear { focusesGroup = true }
    }

    /// Copies the code for this device only, and clears it from the pasteboard after two minutes.
    private func copy() {
        guard let code = viewModel.code else { return }
        UIPasteboard.general.setItems(
            [[UTType.plainText.identifier: code]],
            options: [.localOnly: true, .expirationDate: Date.now.addingTimeInterval(120)])
    }
}
