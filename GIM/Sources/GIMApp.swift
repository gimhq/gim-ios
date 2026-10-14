import GIMUI
import SwiftUI

@main
struct GIMApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
    }
}
