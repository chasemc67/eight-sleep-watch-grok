import SwiftUI

@main
struct EightSleepWatchApp: App {
    @StateObject private var store = SessionStore()

    var body: some Scene {
        WindowGroup {
            WatchControlView(store: store)
                .task { store.start() }
        }
    }
}
