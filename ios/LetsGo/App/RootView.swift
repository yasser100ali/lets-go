import SwiftUI
import SwiftData

/// Map first. Then People, Plans and Passport, and Wren in the round button at the end
/// of the tab bar. The quote opens the app the first time.
struct RootView: View {
    @Environment(LocationService.self) private var location
    @Environment(SyncStatus.self) private var sync
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = HomeModel()
    @AppStorage("splash.seen") private var seenQuote = false

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.tab) {
            Tab("Map", systemImage: "map", value: AppTab.map) {
                HomeView()
            }
            Tab("People", systemImage: "person.2", value: AppTab.people) {
                PeopleView()
            }
            Tab("Plans", systemImage: "calendar", value: AppTab.plans) {
                PlansView()
            }
            Tab("Passport", systemImage: "person.text.rectangle", value: AppTab.passport) {
                PassportTab()
            }
            Tab("Wren", systemImage: "sparkle", value: AppTab.wren, role: .search) {
                WrenView()
            }
        }
        .tint(Palette.accent)
        .environment(model)
        .fullScreenCover(isPresented: $model.showQuote) {
            QuoteSplash(onDone: {
                seenQuote = true
                model.showQuote = false
            }, onInvite: {
                seenQuote = true
                model.showQuote = false
                model.tab = .people
                Task {
                    // Let the cover go before the sheet comes up.
                    try? await Task.sleep(for: .milliseconds(500))
                    model.addingFriend = true
                }
            })
        }
        .onAppear { if !seenQuote { model.showQuote = true } }
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
            try await Sync.refreshPeople(around: center, context: context)
        }
    }
}
