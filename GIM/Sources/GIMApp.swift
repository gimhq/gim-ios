import GIMUI
import SwiftUI

@main
struct GIMApp: App {
    @State private var model = AppModel(signedIn: AppNotifications.signedIn)

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
    }
}
