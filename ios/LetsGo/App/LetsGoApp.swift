import SwiftUI
import SwiftData

@main
struct LetsGoApp: App {
    @State private var location = LocationService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(location)
                .preferredColorScheme(.dark)
                .tint(Lamp.accent)
        }
        .modelContainer(for: [
            Gathering.self, Kitchen.self, MenuItem.self, Drop.self,
            Order.self, Review.self, Stamp.self, TasteNote.self,
        ])
    }
}
