import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(LocationService.self) private var location
    @Environment(SyncStatus.self) private var sync
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: AppTab = .map

    var body: some View {
        TabView(selection: $tab) {
            Tab("Map", systemImage: "map.fill", value: AppTab.map) {
                MapHomeView()
            }
            Tab("Kitchens", systemImage: "takeoutbag.and.cup.and.straw.fill", value: AppTab.kitchens) {
                KitchensView()
            }
            Tab("You", systemImage: "person.crop.circle", value: AppTab.you) {
                PassportView()
            }
        }
        .task { location.start() }
        // Fill in the sample neighborhood and pull from the server when the
        // neighborhood changes, and whenever the app comes back.
        .task(id: location.center.roundedKey) {
            if CityListings.covers(location.center) { CityListings.refresh(context: context) }
            await SampleNeighborhood.refreshIfNeeded(around: location.center, context: context)
            await pull()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                // Weekly listings roll forward, so refresh them when the app comes back.
                if CityListings.covers(location.center) { CityListings.refresh(context: context) }
                Task { await pull() }
            }
        }
    }

    private func pull() async {
        let center = location.center
        await sync.run { () throws(APIError) in
            try await Sync.refresh(around: center, context: context)
        }
    }
}

enum AppTab: Hashable {
    case map, kitchens, you
}
