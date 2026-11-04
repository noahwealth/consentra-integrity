import SwiftUI

@main
@MainActor
struct ConsentraApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootTabs()
                .environment(model)
                .tint(Theme.indigo)
        }
    }
}
