import SwiftUI
import SwiftData

@main
struct ZoeApp: App {
    @StateObject private var appState = AppState()

    private static let sharedModelContainer: ModelContainer = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true, attributes: nil)
        let schema = Schema([LibraryItem.self])
        let config = ModelConfiguration(schema: schema, url: appSupport.appendingPathComponent("default.store"))
        do {
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            CaptureView()
                .environmentObject(appState)
        }
        .modelContainer(Self.sharedModelContainer)
    }
}
