import AppKit
import Foundation
import Observation

/// One kind of unneeded data Tidy can remove, with exactly the files it would touch.
struct CleanupTarget: Identifiable, Sendable {
    enum Method: Sendable {
        /// Deleted for good: apps and Xcode rebuild these on their own.
        case delete
        /// Moved to the Trash, so it can be restored. Space comes back once the Trash is emptied.
        case trash
    }

    let id: String
    let title: String
    let explanation: String
    let icon: String
    let method: Method
    let entries: [URL]
    let size: Int64
    let isRecommended: Bool
}

enum CleanupScanner {
    static let installerExtensions: Set<String> = ["dmg", "pkg", "mpkg"]

    /// Lowercased names and bundle ids of open apps. Their caches are skipped because they're in use.
    @MainActor
    static func runningNames() -> Set<String> {
        var names = Set<String>()
        for app in NSWorkspace.shared.runningApplications {
            if let name = app.localizedName { names.insert(name.lowercased()) }
            if let id = app.bundleIdentifier?.lowercased() {
                names.insert(id)
                // com.google.Chrome keeps its cache in Caches/Google.
                let parts = id.split(separator: ".")
                if parts.count > 1 { names.insert(String(parts[1])) }
            }
        }
        return names
    }

    static func scan(library: URL, installerFolders: [URL], running: Set<String>) -> [CleanupTarget] {
        var targets: [CleanupTarget] = []

        func addFolder(_ id: String, _ title: String, _ explanation: String, _ icon: String,
                       path: String, recommended: Bool = true, skip: (String) -> Bool = { _ in false }) {
            let entries = children(of: library.appending(path: path)).filter { !skip($0.lastPathComponent.lowercased()) }
            add(id, title, explanation, icon, .delete, entries, recommended)
        }

        func add(_ id: String, _ title: String, _ explanation: String, _ icon: String,
                 _ method: CleanupTarget.Method, _ entries: [URL], _ recommended: Bool) {
            let size = entries.reduce(Int64(0)) { $0 + sizeOf($1) }
            guard size > 0 else { return }
            targets.append(CleanupTarget(id: id, title: title, explanation: explanation, icon: icon, method: method,
                                         entries: entries, size: size, isRecommended: recommended))
        }

        // Apple's own caches are left alone, along with those of anything currently open.
        addFolder("caches", "App caches",
                  "Temporary files apps keep to load faster. Apps make new ones as needed, so some may feel slower the first time.",
                  "app.badge", path: "Caches") { $0.hasPrefix("com.apple.") || running.contains($0) }
        addFolder("logs", "App logs",
                  "Records apps write about what they did, mostly useful for troubleshooting. Open apps are skipped.",
                  "doc.text", path: "Logs") { running.contains($0) }
        if !running.contains("com.apple.dt.xcode") {
            addFolder("derivedData", "Xcode build files",
                      "Leftovers from building apps. Xcode recreates them next time you build.",
                      "hammer", path: "Developer/Xcode/DerivedData")
        }
        if !running.contains("com.apple.iphonesimulator") {
            addFolder("simulatorCaches", "iPhone Simulator caches",
                      "Temporary Simulator files. They come back when needed.",
                      "iphone", path: "Developer/CoreSimulator/Caches")
        }
        addFolder("deviceSupport", "iPhone debugging files",
                  "Xcode copies these from your iPhone. It copies them again next time you connect, which takes a few minutes.",
                  "cable.connector", path: "Developer/Xcode/iOS DeviceSupport", recommended: false)

        let installers = installerFolders.flatMap { folder in
            (children(of: folder) + children(of: folder.appending(path: FileCategory.installers.folderName)))
                .filter { installerExtensions.contains($0.pathExtension.lowercased()) }
        }
        add("installers", "Old app installers",
            "Disk images and installers (.dmg, .pkg) in Downloads and Desktop. Once an app is installed you usually don't need them. They go to the Trash.",
            "shippingbox", .trash, installers, false)

        return targets
    }

    /// Removes a target's files and reports the bytes removed and how many couldn't be.
    static func clean(_ target: CleanupTarget) -> (bytes: Int64, failures: Int) {
        let fm = FileManager.default
        var bytes: Int64 = 0
        var failures = 0
        for entry in target.entries {
            let size = sizeOf(entry)
            do {
                switch target.method {
                case .delete: try fm.removeItem(at: entry)
                case .trash: try fm.trashItem(at: entry, resultingItemURL: nil)
                }
                bytes += size
            } catch {
                failures += 1
            }
        }
        return (bytes, failures)
    }

    private static func children(of folder: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
    }

    private static func sizeOf(_ url: URL) -> Int64 {
        // A link is only a pointer: removing it frees nothing, and what it points at isn't ours to measure.
        if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true { return 0 }
        var ignored: [SizedItem] = []
        return StorageScanner.walk(url, collectLarge: false, large: &ignored)
    }
}

@MainActor
@Observable
final class CleanupModel {
    var targets: [CleanupTarget] = []
    var selected = Set<String>()
    var isScanning = false
    var isCleaning = false
    var hasScanned = false
    var result: String?
    /// True once something has gone to the Trash, so the screen can point there.
    var movedToTrash = false

    var selectedTargets: [CleanupTarget] { targets.filter { selected.contains($0.id) } }
    var selectedSize: Int64 { selectedTargets.reduce(0) { $0 + $1.size } }
    var recommendedSize: Int64 { targets.filter(\.isRecommended).reduce(0) { $0 + $1.size } }

    func scan() async {
        isScanning = true
        let running = CleanupScanner.runningNames()
        let library = URL.libraryDirectory
        let folders = [URL.downloadsDirectory, URL.desktopDirectory]
        let found = await Task.detached(priority: .userInitiated) {
            CleanupScanner.scan(library: library, installerFolders: folders, running: running)
        }.value
        targets = found
        selected = Set(found.filter(\.isRecommended).map(\.id))
        isScanning = false
        hasScanned = true
    }

    func cleanSelected() async {
        let chosen = selectedTargets
        guard !chosen.isEmpty else { return }
        isCleaning = true
        let results = await Task.detached(priority: .userInitiated) {
            chosen.map { (target: $0, outcome: CleanupScanner.clean($0)) }
        }.value

        let deleted = results.filter { $0.target.method == .delete }
        let trashed = results.filter { $0.target.method == .trash }
        let freed = deleted.reduce(Int64(0)) { $0 + $1.outcome.bytes }
        let inTrash = trashed.reduce(Int64(0)) { $0 + $1.outcome.bytes }
        let failures = results.reduce(0) { $0 + $1.outcome.failures }

        var parts: [String] = []
        if !deleted.isEmpty {
            parts.append("Freed \(freed.byteString) by clearing \(deleted.map { $0.target.title.lowercased() }.joined(separator: ", ")).")
        }
        if inTrash > 0 {
            parts.append("Moved \(inTrash.byteString) of installers to the Trash. Empty the Trash to get that space back.")
            movedToTrash = true
        }
        if failures > 0 {
            parts.append("\(failures) item\(failures == 1 ? " was" : "s were") in use or protected, so \(failures == 1 ? "it was" : "they were") left alone.")
        }
        let summary = parts.joined(separator: " ")
        result = summary
        ActivityLog.shared.add(summary, icon: "sparkles")
        isCleaning = false
        await scan()
    }
}
