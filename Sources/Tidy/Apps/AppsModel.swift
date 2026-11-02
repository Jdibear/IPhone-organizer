import AppKit
import CoreServices
import Foundation
import Observation

struct AppInfo: Identifiable, Sendable {
    let url: URL
    let name: String
    let category: String
    var version: String?
    var lastUsed: Date?
    var size: Int64?
    /// Apps built into macOS can't be removed.
    var isSystem = false

    var id: URL { url }

    /// Unknown dates don't count: Spotlight doesn't always know, and an app shouldn't look unused because of that.
    var isUnused: Bool {
        guard let lastUsed else { return false }
        return lastUsed < Calendar.current.date(byAdding: .month, value: -6, to: .now)!
    }
}

enum AppsScanner {
    static let categoryNames: [String: String] = [
        "business": "Productivity", "productivity": "Productivity", "finance": "Productivity",
        "developer-tools": "Developer Tools",
        "education": "Education", "reference": "Education", "books": "Education",
        "entertainment": "Entertainment", "music": "Entertainment", "video": "Entertainment",
        "games": "Games",
        "graphics-design": "Photos & Design", "photography": "Photos & Design",
        "healthcare-fitness": "Lifestyle", "lifestyle": "Lifestyle", "food-and-drink": "Lifestyle",
        "travel": "Lifestyle", "shopping": "Lifestyle", "sports": "Lifestyle",
        "medical": "Lifestyle", "navigation": "Lifestyle", "weather": "Lifestyle", "news": "Lifestyle",
        "social-networking": "Communication",
        "utilities": "Utilities",
    ]
    static let otherCategory = "Other"

    /// Friendly group for an app's `LSApplicationCategoryType`, such as public.app-category.developer-tools.
    /// Game categories all look like public.app-category.action-games.
    static func categoryName(for type: String?) -> String {
        guard let key = type?.lowercased().replacingOccurrences(of: "public.app-category.", with: "") else {
            return otherCategory
        }
        return categoryNames[key] ?? (key.hasSuffix("-games") ? "Games" : otherCategory)
    }

    /// Every app directly in `folders`, or one folder level down (like /Applications/Utilities).
    static func apps(in folders: [URL]) -> [AppInfo] {
        var found: [AppInfo] = []
        for folder in folders {
            for child in contents(of: folder) {
                if child.pathExtension == "app" {
                    found.append(info(for: child))
                } else if (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    found += contents(of: child).filter { $0.pathExtension == "app" }.map(info(for:))
                }
            }
        }
        return found.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Moves an app into `applications`, refusing to replace one that's already there.
    static func move(_ app: URL, into applications: URL) throws -> URL {
        let destination = applications.appending(path: app.lastPathComponent)
        try FileManager.default.moveItem(at: app, to: destination)
        return destination
    }

    private static func contents(of folder: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
    }

    private static func info(for url: URL) -> AppInfo {
        let plist = Bundle(url: url)?.infoDictionary
        let name = (plist?["CFBundleDisplayName"] as? String) ?? url.deletingPathExtension().lastPathComponent
        var lastUsed: Date?
        if let item = MDItemCreateWithURL(nil, url as CFURL) {
            lastUsed = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
        }
        return AppInfo(
            url: url,
            name: name,
            category: categoryName(for: plist?["LSApplicationCategoryType"] as? String),
            version: plist?["CFBundleShortVersionString"] as? String,
            lastUsed: lastUsed,
            isSystem: url.resolvingSymlinksInPath().path.hasPrefix("/System/"))
    }
}

@MainActor
@Observable
final class AppsModel {
    static let applicationsFolder = URL(filePath: "/Applications")

    var apps: [AppInfo] = []
    /// Apps sitting in Downloads or on the Desktop instead of the Applications folder.
    var strays: [AppInfo] = []
    var isScanning = false
    var hasScanned = false
    var status: String?

    var unused: [AppInfo] { apps.filter { $0.isUnused && !$0.isSystem } }
    var largest: [AppInfo] { apps.sorted { ($0.size ?? 0) > ($1.size ?? 0) } }

    var groups: [(name: String, apps: [AppInfo])] {
        Dictionary(grouping: apps, by: \.category)
            .map { (name: $0.key, apps: $0.value) }
            .sorted { lhs, rhs in
                // "Other" reads best last.
                if (lhs.name == AppsScanner.otherCategory) != (rhs.name == AppsScanner.otherCategory) {
                    return rhs.name == AppsScanner.otherCategory
                }
                return lhs.name < rhs.name
            }
    }

    func scan() async {
        isScanning = true
        let folders = [Self.applicationsFolder, URL.homeDirectory.appending(path: "Applications")]
        let strayFolders = [URL.downloadsDirectory, URL.desktopDirectory]
        let (found, loose) = await Task.detached(priority: .userInitiated) {
            (AppsScanner.apps(in: folders), AppsScanner.apps(in: strayFolders))
        }.value
        apps = found
        strays = loose
        isScanning = false
        hasScanned = true

        // Names show straight away; sizes fill in as each app is measured.
        for app in found + loose {
            let size = await Task.detached(priority: .utility) {
                var ignored: [SizedItem] = []
                return StorageScanner.walk(app.url, collectLarge: false, large: &ignored)
            }.value
            if let index = apps.firstIndex(where: { $0.id == app.id }) { apps[index].size = size }
            if let index = strays.firstIndex(where: { $0.id == app.id }) { strays[index].size = size }
        }
    }

    func isRunning(_ app: AppInfo) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleURL?.standardizedFileURL == app.url.standardizedFileURL }
    }

    func moveToApplications(_ app: AppInfo) {
        do {
            let moved = try AppsScanner.move(app.url, into: Self.applicationsFolder)
            strays.removeAll { $0.id == app.id }
            var updated = AppInfo(url: moved, name: app.name, category: app.category, version: app.version,
                                  lastUsed: app.lastUsed, size: app.size)
            updated.isSystem = false
            apps.append(updated)
            apps.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            status = "Moved \(app.name) to your Applications folder."
            ActivityLog.shared.add("Moved \(app.name) to your Applications folder.", icon: "square.grid.2x2")
        } catch {
            status = "Couldn't move \(app.name). There may already be a copy in Applications."
        }
    }

    func trash(_ app: AppInfo) {
        do {
            try FileManager.default.trashItem(at: app.url, resultingItemURL: nil)
            apps.removeAll { $0.id == app.id }
            strays.removeAll { $0.id == app.id }
            let text = "Moved \(app.name) to the Trash\(app.size.map { " (\($0.byteString))" } ?? "")."
            status = text + " To get it back, open the Trash and choose Put Back."
            ActivityLog.shared.add(text, icon: "trash")
        } catch {
            status = "macOS wouldn't let Tidy remove \(app.name). Use the magnifying glass to find it, then drag it to the Trash."
        }
    }
}
