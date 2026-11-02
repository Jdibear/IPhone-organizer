import SwiftUI
import SwiftData

@main
struct TidyApp: App {
    let container: ModelContainer = {
        let dir = URL.applicationSupportDirectory.appending(path: "Tidy", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let config = ModelConfiguration(url: dir.appending(path: "Tidy.store"))
        do {
            return try ModelContainer(for: TaskItem.self, Note.self, configurations: config)
        } catch {
            fatalError("Could not open Tidy's database: \(error)")
        }
    }()

    @State private var autoTidy = AutoTidyController()

    var body: some Scene {
        WindowGroup("Tidy", id: "main") {
            ContentView()
                .environment(autoTidy)
        }
        .modelContainer(container)
        .defaultSize(width: 1100, height: 720)
        // Always open a window on launch, even if the last one was closed; otherwise clicking Tidy
        // looks like it does nothing.
        .defaultLaunchBehavior(.presented)
        .restorationBehavior(.disabled)

        // Keeps Tidy running (and sorting Downloads) after the window is closed.
        MenuBarExtra("Tidy", systemImage: "tray.and.arrow.down") {
            AutoTidyMenu()
                .environment(autoTidy)
        }
        .menuBarExtraStyle(.window)
    }
}

enum SidebarItem: String, CaseIterable, Identifiable {
    case overview, files, apps, cleanup, storage, photos, tasks

    var id: Self { self }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .files: "Downloads & Desktop"
        case .apps: "Apps"
        case .cleanup: "Clean Up"
        case .storage: "Storage"
        case .photos: "Photos"
        case .tasks: "Tasks & Notes"
        }
    }

    var icon: String {
        switch self {
        case .overview: "sparkles"
        case .files: "folder.badge.gearshape"
        case .apps: "square.grid.2x2"
        case .cleanup: "trash.circle"
        case .storage: "internaldrive"
        case .photos: "photo.on.rectangle"
        case .tasks: "checklist"
        }
    }
}

struct ContentView: View {
    @State private var selection: SidebarItem? = .overview
    // Models live here so each section keeps its results when you switch away.
    @State private var files = FolderTidyModel(folder: .downloadsDirectory)
    @State private var apps = AppsModel()
    @State private var cleanup = CleanupModel()
    @State private var storage = StorageModel()
    @State private var photos = PhotosModel()

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.title, systemImage: item.icon).tag(item)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } detail: {
            switch selection ?? .overview {
            case .overview: OverviewView(selection: $selection, files: files, apps: apps, cleanup: cleanup, photos: photos)
            case .files: FolderTidyView(model: files)
            case .apps: AppsView(model: apps)
            case .cleanup: CleanupView(model: cleanup)
            case .storage: StorageView(model: storage)
            case .photos: PhotosView(model: photos)
            case .tasks: TasksNotesView()
            }
        }
    }
}
