import SwiftUI
import SwiftData

@main
struct ZoeApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            TabView {
                CaptureView()
                    .tabItem { Label("Capture", systemImage: "camera") }

                LibraryView()
                    .tabItem { Label("Library", systemImage: "photo.on.rectangle") }
            }
            .environmentObject(appState)
        }
        .modelContainer(for: LibraryItem.self)
    }
}
