import SwiftUI
import SwiftData

/// Five tabs (Today, Map, Lists, Kitchens, You) with the now bar above the tab bar.
struct RootView: View {
    @Environment(LocationService.self) private var location
    @Environment(SyncStatus.self) private var sync
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = HomeModel()

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.tab) {
            Tab("Today", systemImage: "sparkles", value: AppTab.today) {
                TodayView()
            }
            Tab("Map", systemImage: "map.fill", value: AppTab.map) {
                HomeView()
            }
            Tab("Lists", systemImage: "checklist", value: AppTab.lists) {
                ListsView()
            }
            Tab("Kitchens", systemImage: "takeoutbag.and.cup.and.straw.fill", value: AppTab.kitchens) {
                NavigationStack {
                    ScrollView { KitchensView() }
                        .scrollIndicators(.hidden)
                        .background(Palette.bg)
                        .navigationTitle("Kitchens")
                        .navigationDestination(for: Kitchen.self) { KitchenView(kitchen: $0) }
                        .navigationDestination(for: Order.self) { OrderStatusView(order: $0) }
                        .navigationDestination(for: MyKitchenRoute.self) { _ in MyKitchenView() }
                }
            }
            Tab("You", systemImage: "person.crop.circle", value: AppTab.you) {
                NavigationStack {
                    ScrollView { PassportView() }
                        .scrollIndicators(.hidden)
                        .background(Palette.bg)
                }
            }
        }
        .tabViewBottomAccessory { NowBar() }
        .environment(model)
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
        if CityListings.covers(center), await CityListings.update() { CityListings.refresh(context: context) }
        await sync.run { () throws(APIError) in
            try await Sync.refresh(around: center, context: context)
        }
    }
}
