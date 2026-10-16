import GIMFeatures
import SwiftUI

/// Adds a hub by its URL (`addHub`); closes once gim-core listed it.
struct AddHubScreen: View {
    @State private var viewModel: AddHubViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusesUrl: Bool

    init(viewModel: AddHubViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Form {
            Section {
                TextField("https://hub.example.eu", text: $viewModel.url)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusesUrl)
                    .accessibilityIdentifier("addHub.url")
                    .submitLabel(.done)
                    .onSubmit(submit)
                ValidationMessage(text: viewModel.urlError)
            } header: {
                Text("Hub Address")
            } footer: {
                Text("Your messages are also kept on this hub, and it takes over while your other hubs are down.")
            }

            Section {
                Button(action: submit) {
                    HStack {
                        Spacer()
                        if viewModel.isSubmitting {
                            ProgressView()
                        } else {
                            Text("Add Hub").bold()
                        }
                        Spacer()
                    }
                }
                .disabled(!viewModel.canSubmit)
                .accessibilityIdentifier("addHub.submit")
            } footer: {
                if let error = viewModel.errorMessage {
                    Text(error).foregroundStyle(.red).accessibilityIdentifier("addHub.error")
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Add Hub")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { focusesUrl = true }
        .onChange(of: viewModel.addedHub) { _, hub in
            if hub != nil { dismiss() }
        }
    }

    private func submit() {
        focusesUrl = false
        Task { await viewModel.submit() }
    }
}
