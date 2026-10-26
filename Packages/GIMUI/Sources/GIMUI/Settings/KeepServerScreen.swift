import GIMFeatures
import SwiftUI

/// Settings → Keep server: turn the keep server on or off, change its address or go back to the default one. The
/// choice applies to the client created next, so a change asks to reopen the app.
struct KeepServerScreen: View {
    @State private var model: KeepServerViewModel

    init(model: KeepServerViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { model.isOn }, set: { model.setOn($0) })) {
                    Text("Use a keep server", tableName: "Settings", bundle: .module)
                }
                .accessibilityIdentifier("keepServer.toggle")
            } footer: {
                Text(
                    "Backs up your privacy settings and receives reports. Your data is encrypted.",
                    tableName: "Settings", bundle: .module)
            }
            if model.isOn {
                Section {
                    TextField(text: $model.draft, prompt: Text(verbatim: KeepServer.builtInUrl)) {
                        Text("Address", tableName: "Settings", bundle: .module)
                    }
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit { model.save() }
                    .accessibilityIdentifier("keepServer.address")
                    Button {
                        model.save()
                    } label: {
                        Text("Save", tableName: "Common", bundle: .module)
                    }
                    .disabled(model.draft == model.url)
                    .accessibilityIdentifier("keepServer.save")
                    if !model.isDefault {
                        Button {
                            model.resetToDefault()
                        } label: {
                            Text("Use the default keep server", tableName: "Settings", bundle: .module)
                        }
                        .accessibilityIdentifier("keepServer.reset")
                    }
                } header: {
                    Text("Address", tableName: "Settings", bundle: .module)
                } footer: {
                    if let error = model.errorKind {
                        Text(error.text).foregroundStyle(.red)
                    }
                }
            }
            if model.needsRestart {
                Section {
                    Text("Changes apply the next time you open gim.", tableName: "Settings", bundle: .module)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("keepServer.restart")
                }
            }
        }
        .navigationTitle(Text("Keep server", tableName: "Settings", bundle: .module))
        .navigationBarTitleDisplayMode(.inline)
    }
}
