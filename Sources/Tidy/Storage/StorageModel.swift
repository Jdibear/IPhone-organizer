import Foundation
import Observation

struct SizedItem: Identifiable, Hashable, Sendable {
    let url: URL
    let size: Int64
    var note: String? = nil
    var isPackage = false

    var id: URL { url }

    /// Only plain files outside ~/Library can be trashed from Tidy; everything else is "Show in Finder" only,
    /// so a click here can never break an app or a Photos library.
    var canTrash: Bool {
        !isPackage && !url.path.hasPrefix(URL.libraryDirectory.path + "/")
    }
}

struct StorageReport: Sendable {
    var totalBytes: Int64 = 0
    var freeBytes: Int64 = 0
    var quickWins: [SizedItem] = []
    var folders: [SizedItem] = []
    var largeFiles: [SizedItem] = []
}

@MainActor
@Observable
final class StorageModel {
    var report: StorageReport?
    var isScanning = false
    var progress = ""
    var status: String?
    private var scanTask: Task<Void, Never>?

    func scan() {
        scanTask?.cancel()
        isScanning = true
        status = nil
        scanTask = Task {
            let report = await Task.detached(priority: .userInitiated) {
                StorageScanner.scan { name in
                    Task { @MainActor in self.progress = name }
                }
            }.value
            if !Task.isCancelled { self.report = report }
            isScanning = false
        }
    }

    func cancel() {
        scanTask?.cancel()
        isScanning = false
    }

    func trash(_ item: SizedItem) {
        do {
            try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
            report?.largeFiles.removeAll { $0.id == item.id }
            status = "Moved \(item.url.lastPathComponent) to the Trash (\(item.size.byteString))."
        } catch {
            status = "Couldn't move \(item.url.lastPathComponent) to the Trash: \(error.localizedDescription)"
        }
    }
}

enum StorageScanner {
    static let largeFileThreshold: Int64 = 200 * 1_000_000

    static func scan(progress: @Sendable (String) -> Void) -> StorageReport {
        var report = StorageReport()
        let fm = FileManager.default
        let home = URL.homeDirectory

        if let values = try? URL(filePath: "/").resourceValues(forKeys: [
            .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
        ]) {
            report.totalBytes = Int64(values.volumeTotalCapacity ?? 0)
            report.freeBytes = values.volumeAvailableCapacityForImportantUsage ?? 0
        }

        // Well-known space hogs, especially ones tied to iPhones.
        let library = URL.libraryDirectory
        let known: [(URL, String)] = [
            (library.appending(path: "Application Support/MobileSync/Backup"), "Old iPhone & iPad backups"),
            (library.appending(path: "Developer/Xcode/iOS DeviceSupport"), "iPhone debugging symbols (Xcode)"),
            (library.appending(path: "Developer/Xcode/DerivedData"), "Xcode build files — safe to delete"),
            (library.appending(path: "Caches"), "App caches — apps rebuild these"),
        ]
        for (url, note) in known where fm.fileExists(atPath: url.path) {
            if Task.isCancelled { return report }
            progress(note)
            var ignored: [SizedItem] = []
            let size = walk(url, collectLarge: false, large: &ignored)
            if size > 0 { report.quickWins.append(SizedItem(url: url, size: size, note: note)) }
        }

        // Every top-level folder in your home folder, plus the biggest files inside them.
        let children = (try? fm.contentsOfDirectory(
            at: home, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        var large: [SizedItem] = []
        for child in children {
            if Task.isCancelled { return report }
            progress(child.lastPathComponent)
            let size = walk(child, collectLarge: true, large: &large)
            if size > 0 { report.folders.append(SizedItem(url: child, size: size)) }
        }
        report.folders.sort { $0.size > $1.size }
        report.largeFiles = Array(large.sorted { $0.size > $1.size }.prefix(60))
        return report
    }

    /// Total allocated size of `url`. Packages (apps, Photos libraries…) are measured but reported as a whole.
    static func walk(_ url: URL, collectLarge: Bool, large: inout [SizedItem]) -> Int64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isPackageKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        if let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true {
            let size = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            if collectLarge && size >= largeFileThreshold { large.append(SizedItem(url: url, size: size)) }
            return size
        }
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in true })
        else { return 0 }

        var total: Int64 = 0
        while let item = enumerator.nextObject() as? URL {
            if Task.isCancelled { break }
            guard let values = try? item.resourceValues(forKeys: keys) else { continue }
            if values.isPackage == true {
                enumerator.skipDescendants()
                var ignored: [SizedItem] = []
                let size = walk(item, collectLarge: false, large: &ignored)
                total += size
                if collectLarge && size >= largeFileThreshold {
                    large.append(SizedItem(url: item, size: size, isPackage: true))
                }
            } else if values.isRegularFile == true {
                let size = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
                total += size
                if collectLarge && size >= largeFileThreshold { large.append(SizedItem(url: item, size: size)) }
            }
        }
        return total
    }
}
