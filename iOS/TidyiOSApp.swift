import SwiftUI
import SwiftData

@main
struct TidyiOSApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [TaskItem.self, Note.self])
    }
}

struct RootView: View {
    // Models live here so each tab keeps its results when you switch away.
    @State private var photos = PhotosModel()
    @State private var folder = FolderAccess()

    var body: some View {
        TabView {
            Tab("Photos", systemImage: "photo.on.rectangle") {
                NavigationStack { PhotosScreen(model: photos) }
            }
            Tab("Files", systemImage: "folder") {
                NavigationStack { FilesScreen(access: folder) }
            }
            Tab("Tasks", systemImage: "checklist") {
                NavigationStack { TasksScreen() }
            }
            Tab("Notes", systemImage: "note.text") {
                NotesScreen()
            }
        }
    }
}
