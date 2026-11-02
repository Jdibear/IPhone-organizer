import SwiftUI

/// The first screen: says in plain words what each part of Tidy does, what it found, and what it has done.
struct OverviewView: View {
    @Binding var selection: SidebarItem?
    let files: FolderTidyModel
    let apps: AppsModel
    let cleanup: CleanupModel
    let photos: PhotosModel
    @Environment(AutoTidyController.self) private var autoTidy
    private var log: ActivityLog { .shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tidy keeps your Mac organized.").font(.title2.bold())
                    Text("Here's what each part does and what it found. Tidy shows you the plan first and doesn't remove anything until you click.")
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14)], spacing: 14) {
                    card(.files, "Sorts loose files into folders like Documents and Images, and sends exact duplicates to the Trash. Undo puts everything back.",
                         status: filesStatus)
                    card(.apps, "Groups your apps by what they're for, and points out big ones and ones you've stopped using.",
                         status: appsStatus)
                    card(.cleanup, "Removes caches, logs and other leftovers your Mac doesn't need, to free up space.",
                         status: cleanupStatus)
                    card(.storage, "Measures your folders and finds your biggest files, so you can see what's filling your disk.",
                         status: "Scan to see what's using your disk")
                    card(.photos, "Finds screenshots, real duplicate photos and long videos you may want to delete.",
                         status: photos.hasAccess ? "\(photos.screenshots.count) screenshots, \(photos.duplicateGroups.count) duplicate sets" : "Needs your permission first")
                    card(.tasks, "A simple to-do list and notes, kept on this Mac.", status: nil)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("What Tidy has done").font(.title3.bold())
                    if log.entries.isEmpty {
                        Text("Nothing yet. Everything Tidy moves or removes will be listed here.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(log.entries.prefix(15)) { entry in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Image(systemName: entry.icon)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 18)
                                Text(entry.text).fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 12)
                                Text(entry.date, format: .relative(presentation: .named))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 1000, alignment: .leading)
        }
        .navigationTitle("Overview")
        .task {
            // Fills in the numbers on the cards. Only looks; nothing is changed.
            if !cleanup.hasScanned { await cleanup.scan() }
        }
        .task {
            if !apps.hasScanned { await apps.scan() }
        }
    }

    private var filesStatus: String {
        let sorting = autoTidy.isEnabled ? "Auto-sort is on" : "Auto-sort is off"
        if files.isWorking || files.actions.isEmpty { return sorting }
        return "\(sorting) · \(files.actions.count) item\(files.actions.count == 1 ? "" : "s") in \(files.folder.lastPathComponent) to sort"
    }

    private var appsStatus: String {
        guard apps.hasScanned else { return "Looking…" }
        let unused = apps.unused.count
        return "\(apps.apps.count) apps" + (unused > 0 ? " · \(unused) not opened in 6 months" : "")
    }

    private var cleanupStatus: String {
        guard cleanup.hasScanned else { return "Looking…" }
        return cleanup.recommendedSize > 0 ? "\(cleanup.recommendedSize.byteString) can be freed" : "Nothing to clean right now"
    }

    private func card(_ item: SidebarItem, _ explanation: String, status: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(item.title, systemImage: item.icon).font(.headline)
            Text(explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HStack {
                if let status {
                    Text(status).font(.callout.weight(.medium)).lineLimit(2)
                }
                Spacer()
                Button("Open") { selection = item }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }
}
