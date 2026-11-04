import SwiftUI

@MainActor
struct RootTabs: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            PassportHomeView()
                .tabItem { Label("Passport", systemImage: "person.text.rectangle") }
                .tag(Tab.passport)
            MyHealthView()
                .tabItem { Label("Health", systemImage: "heart") }
                .tag(Tab.health)
            ShareHomeView()
                .tabItem { Label("Share", systemImage: "square.and.arrow.up") }
                .tag(Tab.share)
            ActivityView()
                .tabItem { Label("Activity", systemImage: "clock") }
                .tag(Tab.activity)
        }
        .task { await model.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refresh() } }
        }
    }
}
