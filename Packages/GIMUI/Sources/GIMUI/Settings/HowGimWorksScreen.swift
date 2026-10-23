import SwiftUI

/// Explains in plain words how gim keeps the account and messages on the user's devices.
struct HowGimWorksScreen: View {
    private static let topics = [
        "explainer_no_phone_number", "explainer_on_your_devices", "explainer_locked_messages", "explainer_account_id",
        "explainer_recovery_key",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("explainer_intro", tableName: "Explainer", bundle: .module)
                ForEach(Self.topics, id: \.self) { topic in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(LocalizedStringKey(topic + "_title"), tableName: "Explainer", bundle: .module)
                            .font(.headline)
                        Text(LocalizedStringKey(topic + "_body"), tableName: "Explainer", bundle: .module)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle(Text("explainer_title", tableName: "Explainer", bundle: .module))
        .navigationBarTitleDisplayMode(.inline)
    }
}
