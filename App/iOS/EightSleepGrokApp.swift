import SwiftUI

@main
struct EightSleepGrokApp: App {
    @StateObject private var store = SessionStore()

    var body: some Scene {
        WindowGroup {
            PhoneView(store: store)
                .task { store.start() }
        }
    }
}
