import Foundation
import Observation
import ServiceManagement

struct AutoTidyEvent: Identifiable {
    let id = UUID()
    let from: URL
    let to: URL
    let category: FileCategory
    let date = Date.now
}

/// Watches Downloads and sorts each new file into its category folder once it has finished downloading.
/// Files that were already there when watching started are left alone — use Tidy for those.
@MainActor
@Observable
final class AutoTidyController {
    static let enabledKey = "autoTidyDownloads"

    let folder = URL.downloadsDirectory

    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            isEnabled ? start() : stop()
        }
    }

    private(set) var recent: [AutoTidyEvent] = []
    /// Bumped after every batch so open views can refresh.
    private(set) var lastSortDate: Date?
    private(set) var status: String?
    private(set) var opensAtLogin = SMAppService.mainApp.status == .enabled

    /// Names to leave in place: files present when watching started, files put back with Undo,
    /// and files that couldn't be moved.
    private var ignored = Set<String>()
    private var source: DispatchSourceFileSystemObject?
    private var pendingCheck: Task<Void, Never>?

    init() {
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        if isEnabled { start() }
    }

    private func start() {
        guard source == nil else { return }
        ignored = Set(((try? TidyPlanner.looseFiles(in: folder)) ?? []).map(\.url.lastPathComponent))

        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else {
            status = "Can't watch Downloads. Allow access in System Settings › Privacy & Security › Files & Folders."
            return
        }
        // .write on a directory fires when entries are added, removed or renamed —
        // which is exactly what a browser does when a download finishes.
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scheduleCheck(after: .seconds(2)) }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
        status = nil
    }

    private func stop() {
        source?.cancel()
        source = nil
        pendingCheck?.cancel()
        status = nil
    }

    private func scheduleCheck(after delay: Duration) {
        pendingCheck?.cancel()
        pendingCheck = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await sortNewArrivals()
        }
    }

    private func sortNewArrivals() async {
        let folder = folder
        let ignored = ignored
        let (ready, stillWriting) = await Task.detached(priority: .utility) {
            Self.finishedFiles(in: folder, ignoring: ignored)
        }.value

        let fm = FileManager.default
        var moved: [AutoTidyEvent] = []
        for file in ready {
            let target = TidyPlanner.uniqueURL(for: file.destination(in: folder))
            do {
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: file.url, to: target)
                moved.append(AutoTidyEvent(from: file.url, to: target, category: file.category))
            } catch {
                self.ignored.insert(file.url.lastPathComponent)
            }
        }
        if !moved.isEmpty {
            recent = Array((moved.reversed() + recent).prefix(20))
            lastSortDate = .now
        }
        // Writing into an existing file doesn't touch the folder itself, so poll until it settles.
        if stillWriting { scheduleCheck(after: .seconds(5)) }
    }

    /// New files that have stopped changing, and whether any others are still being written.
    nonisolated private static func finishedFiles(
        in folder: URL, ignoring ignored: Set<String>
    ) -> (ready: [TidyPlanner.LooseFile], stillWriting: Bool) {
        let fresh = ((try? TidyPlanner.looseFiles(in: folder)) ?? [])
            .filter { !ignored.contains($0.url.lastPathComponent) }
        guard !fresh.isEmpty else { return ([], false) }

        Thread.sleep(forTimeInterval: 1.5)
        let now = ((try? TidyPlanner.looseFiles(in: folder)) ?? [])
        let latest = Dictionary(now.map { ($0.url, $0) }, uniquingKeysWith: { a, _ in a })

        var ready: [TidyPlanner.LooseFile] = []
        var stillWriting = false
        for file in fresh {
            guard let again = latest[file.url] else { continue }
            let settled = again.size == file.size
                && again.modified == file.modified
                && again.modified < Date.now.addingTimeInterval(-1)
            if settled { ready.append(again) } else { stillWriting = true }
        }
        return (ready, stillWriting)
    }

    func undo(_ event: AutoTidyEvent) {
        let target = TidyPlanner.uniqueURL(for: event.from)
        guard (try? FileManager.default.moveItem(at: event.to, to: target)) != nil else {
            status = "Couldn't put back \(event.to.lastPathComponent) — it may have been moved already."
            return
        }
        ignored.insert(target.lastPathComponent)
        recent.removeAll { $0.id == event.id }
        lastSortDate = .now
    }

    /// Don't auto-sort these, e.g. files the user just put back with Tidy's own Undo.
    func leaveAlone(_ urls: [URL]) {
        ignored.formUnion(urls.map(\.lastPathComponent))
    }

    func setOpensAtLogin(_ value: Bool) {
        do {
            if value {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            status = nil
        } catch {
            status = "Couldn't change Open at Login: \(error.localizedDescription)"
        }
        opensAtLogin = SMAppService.mainApp.status == .enabled
    }
}
