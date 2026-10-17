import SwiftUI
import SwiftData

@main
struct LetsGoApp: App {
    @State private var location = LocationService()
    @State private var sync = SyncStatus()
    @AppStorage(Appearance.storageKey) private var appearance: Appearance = .system

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(location)
                .environment(sync)
                .preferredColorScheme(appearance.scheme)
                .tint(Palette.accent)
        }
        .modelContainer(for: [
            Gathering.self, Kitchen.self, MenuItem.self, Drop.self,
            Order.self, Review.self, Stamp.self, TasteNote.self,
        ])
    }
}
