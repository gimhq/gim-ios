import GIMFeatures
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Shows the recovery kit (user id and recovery code) once, lets the user copy or save it, then asks for the last
/// characters of the code.
struct RecoveryKitScreen: View {
    @Bindable var viewModel: RecoveryKitViewModel
    @FocusState private var focusesEnding: Bool
    @State private var showsCopied = false

    /// The kit as a file for the share sheet; written while the kit step is on screen.
    private let kitFileUrl = FileManager.default.temporaryDirectory.appendingPathComponent("gim-recovery-kit.txt")

    var body: some View {
        Group {
            if viewModel.isChecking {
                check
            } else {
                kit
            }
        }
        .navigationBarBackButtonHidden()
    }

    private var kit: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Account ID", tableName: "Onboarding", bundle: .module)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(viewModel.userId)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .accessibilityValue(viewModel.userId)
                        .accessibilityIdentifier("recovery.userId")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recovery key", tableName: "Onboarding", bundle: .module)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(viewModel.groupedCode)
                        .font(.title3.monospaced())
                        .accessibilityLabel(viewModel.groupedCode)
                        .accessibilityIdentifier("recovery.code")
                }
            } header: {
                Text("explainer_recovery_key_title", tableName: "Explainer", bundle: .module)
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("explainer_recovery_key_body", tableName: "Explainer", bundle: .module)
                    Text("You see it only now. Save it somewhere safe.", tableName: "Onboarding", bundle: .module)
                }
            }

            Section {
                Button(action: copy) {
                    Label {
                        if showsCopied {
                            Text("Copied", tableName: "Onboarding", bundle: .module)
                        } else {
                            Text("Copy", tableName: "Onboarding", bundle: .module)
                        }
                    } icon: {
                        Image(systemName: showsCopied ? "checkmark" : "doc.on.doc")
                    }
                }
                .accessibilityIdentifier("recovery.copy")
                ShareLink(
                    item: kitFileUrl,
                    preview: SharePreview(Text("gim recovery kit", tableName: "Onboarding", bundle: .module))
                ) {
                    Label {
                        Text("Save as a file", tableName: "Onboarding", bundle: .module)
                    } icon: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                .accessibilityIdentifier("recovery.share")
            }

            Section {
                Button {
                    viewModel.continueToCheck()
                } label: {
                    HStack {
                        Spacer()
                        Text("I saved it", tableName: "Onboarding", bundle: .module).bold()
                        Spacer()
                    }
                }
                .accessibilityIdentifier("recovery.continue")
            }
        }
        .navigationTitle(Text("Your recovery kit", tableName: "Onboarding", bundle: .module))
        .onAppear { try? viewModel.kitText.write(to: kitFileUrl, atomically: true, encoding: .utf8) }
        .onDisappear { try? FileManager.default.removeItem(at: kitFileUrl) }
    }

    private var check: some View {
        Form {
            Section {
                TextField(
                    String(
                        localized: "Last \(viewModel.endingLength) characters", table: "Onboarding", bundle: .module),
                    text: $viewModel.endingInput
                )
                .font(.body.monospaced())
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($focusesEnding)
                .accessibilityIdentifier("recovery.ending")
                .submitLabel(.done)
                .onSubmit { viewModel.confirm() }
                ValidationMessage(text: viewModel.endingError)
            } header: {
                Text("Last \(viewModel.endingLength) characters", tableName: "Onboarding", bundle: .module)
            } footer: {
                Text(
                    "Type the last \(viewModel.endingLength) characters of your recovery key. This makes sure you saved it.",
                    tableName: "Onboarding", bundle: .module)
            }

            Section {
                Button {
                    viewModel.confirm()
                } label: {
                    HStack {
                        Spacer()
                        Text("Confirm", tableName: "Onboarding", bundle: .module).bold()
                        Spacer()
                    }
                }
                .accessibilityIdentifier("recovery.confirm")
            }
        }
        .navigationTitle(Text("Check your recovery key", tableName: "Onboarding", bundle: .module))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    viewModel.showKitAgain()
                } label: {
                    Label {
                        Text("Show the kit again", tableName: "Onboarding", bundle: .module)
                    } icon: {
                        Image(systemName: "chevron.backward")
                    }
                }
                .labelStyle(.titleAndIcon)
            }
        }
        .onAppear { focusesEnding = true }
    }

    /// Copies the kit for this device only, clears it from the pasteboard after two minutes, and shows "Copied"
    /// for two seconds.
    private func copy() {
        UIPasteboard.general.setItems(
            [[UTType.plainText.identifier: viewModel.kitText]],
            options: [.localOnly: true, .expirationDate: Date.now.addingTimeInterval(120)])
        showsCopied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            showsCopied = false
        }
    }
}
