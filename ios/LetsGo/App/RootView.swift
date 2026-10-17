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
            Tab("Wren", systemImage: "sparkles", value: AppTab.wren) {
                WrenView()
            }
            Tab("Kitchens", systemImage: "takeoutbag.and.cup.and.straw.fill", value: AppTab.kitchens) {
                KitchensView()
            }
            Tab("You", systemImage: "person.crop.circle", value: AppTab.you) {
                PassportView()
            }
        }
        .task { location.start() }
        .onChange(of: location.center.roundedKey, initial: true) {
            SampleNeighborhood.refreshIfNeeded(around: location.center, context: context)
        }
        // Pull from the server when the neighborhood changes and whenever the app comes back.
        .task(id: location.center.roundedKey) { await pull() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await pull() } }
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
    case map, wren, kitchens, you
}
