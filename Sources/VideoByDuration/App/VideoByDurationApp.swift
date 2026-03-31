import SwiftUI

@main
struct VideoByDurationApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = FolderStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 900, minHeight: 500)
        }
        .defaultSize(width: 1100, height: 700)
    }
}
