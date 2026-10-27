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

        // Keeps Tidy running (and sorting Downloads) after the window is closed.
        MenuBarExtra("Tidy", systemImage: "tray.and.arrow.down") {
            AutoTidyMenu()
                .environment(autoTidy)
        }
        .menuBarExtraStyle(.window)
    }
}

enum SidebarItem: String, CaseIterable, Identifiable {
    case files, storage, photos, tasks

    var id: Self { self }

    var title: String {
        switch self {
        case .files: "Downloads & Desktop"
        case .storage: "Storage"
        case .photos: "Photos"
        case .tasks: "Tasks & Notes"
        }
    }

    var icon: String {
        switch self {
        case .files: "folder.badge.gearshape"
        case .storage: "internaldrive"
        case .photos: "photo.on.rectangle"
        case .tasks: "checklist"
        }
    }
}

struct ContentView: View {
    @State private var selection: SidebarItem? = .files
    // Models live here so each section keeps its results when you switch away.
    @State private var files = FolderTidyModel(folder: .downloadsDirectory)
    @State private var storage = StorageModel()
    @State private var photos = PhotosModel()

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.title, systemImage: item.icon).tag(item)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } detail: {
            switch selection ?? .files {
            case .files: FolderTidyView(model: files)
            case .storage: StorageView(model: storage)
            case .photos: PhotosView(model: photos)
            case .tasks: TasksNotesView()
            }
        }
    }
}

extension Int64 {
    var byteString: String { ByteCountFormatter.string(fromByteCount: self, countStyle: .file) }
}
