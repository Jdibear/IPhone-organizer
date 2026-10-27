import Foundation
import CryptoKit
import Observation
import UniformTypeIdentifiers

enum FileCategory: String, CaseIterable {
    case screenshots = "Screenshots"
    case images = "Images"
    case documents = "Documents"
    case archives = "Archives"
    case installers = "Installers"
    case videos = "Videos"
    case audio = "Audio"
    case code = "Code"
    case other = "Other"

    /// The subfolder files of this category are moved into.
    var folderName: String { rawValue }

    static func classify(_ url: URL) -> FileCategory {
        let ext = url.pathExtension.lowercased()
        let name = url.lastPathComponent
        if ["dmg", "pkg", "mpkg", "app"].contains(ext) { return .installers }
        guard let type = UTType(filenameExtension: ext) else { return .other }
        if type.conforms(to: .image) {
            let screenshotPrefixes = ["Screenshot", "Screen Shot", "CleanShot", "Schermafbeelding"]
            return screenshotPrefixes.contains(where: name.hasPrefix) ? .screenshots : .images
        }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .videos }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .archive) || type.conforms(to: .diskImage) { return .archives }
        if type.conforms(to: .sourceCode) || type.conforms(to: .script) || type.conforms(to: .json) { return .code }
        if type.conforms(to: .pdf) || type.conforms(to: .text) || type.conforms(to: .presentation)
            || type.conforms(to: .spreadsheet) || type.conforms(to: .compositeContent) {
            return .documents
        }
        return .other
    }
}

struct PlannedAction: Identifiable {
    enum Kind {
        case move(to: URL)
        case trashDuplicate(of: String)
    }

    let id = UUID()
    let source: URL
    let kind: Kind
    let category: FileCategory
    let size: Int64
    let modified: Date
    var included = true

    var isDuplicate: Bool {
        if case .trashDuplicate = kind { return true }
        return false
    }

    /// Untouched for 90+ days.
    var isOld: Bool { modified < Date.now.addingTimeInterval(-90 * 86_400) }

    var actionLabel: String {
        switch kind {
        case .move(let dest): "→ \(dest.deletingLastPathComponent().lastPathComponent)"
        case .trashDuplicate(let original): "Trash (copy of \(original))"
        }
    }
}

enum UndoStep {
    case moved(from: URL, to: URL)
    case trashed(original: URL, trashURL: URL)
}

@MainActor
@Observable
final class FolderTidyModel {
    var folder: URL
    var actions: [PlannedAction] = []
    var isWorking = false
    var status: String?
    var showOnlyOld = false
    private(set) var undoSteps: [UndoStep] = []

    init(folder: URL) {
        self.folder = folder
    }

    var visibleActions: [PlannedAction] {
        showOnlyOld ? actions.filter(\.isOld) : actions
    }

    var includedCount: Int { actions.filter(\.included).count }

    func scan() async {
        isWorking = true
        status = nil
        let folder = folder
        let result = await Task.detached(priority: .userInitiated) {
            try? TidyPlanner.plan(folder: folder)
        }.value
        actions = result ?? []
        isWorking = false
        if result == nil {
            status = "Couldn't read \(folder.lastPathComponent). Allow access in System Settings › Privacy & Security › Files & Folders."
        } else if actions.isEmpty {
            status = "\(folder.lastPathComponent) is already tidy."
        }
    }

    func isIncluded(_ id: UUID) -> Bool {
        actions.first { $0.id == id }?.included ?? false
    }

    func setIncluded(_ id: UUID, _ value: Bool) {
        if let i = actions.firstIndex(where: { $0.id == id }) { actions[i].included = value }
    }

    func setAll(_ value: Bool) {
        let visible = Set(visibleActions.map(\.id))
        for i in actions.indices where visible.contains(actions[i].id) { actions[i].included = value }
    }

    func apply() {
        let fm = FileManager.default
        var steps: [UndoStep] = []
        var failures = 0
        var done = Set<UUID>()
        for action in actions where action.included {
            do {
                switch action.kind {
                case .move(let dest):
                    try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                    let target = TidyPlanner.uniqueURL(for: dest)
                    try fm.moveItem(at: action.source, to: target)
                    steps.append(.moved(from: action.source, to: target))
                case .trashDuplicate:
                    var trashed: NSURL?
                    try fm.trashItem(at: action.source, resultingItemURL: &trashed)
                    if let trashed = trashed as URL? {
                        steps.append(.trashed(original: action.source, trashURL: trashed))
                    }
                }
                done.insert(action.id)
            } catch {
                failures += 1
            }
        }
        undoSteps = steps
        actions.removeAll { done.contains($0.id) }
        status = "Tidied \(done.count) item\(done.count == 1 ? "" : "s")" + (failures > 0 ? " — \(failures) failed." : ".")
    }

    /// Where Undo will put things back.
    var undoOriginals: [URL] {
        undoSteps.map {
            switch $0 {
            case .moved(let from, _): from
            case .trashed(let original, _): original
            }
        }
    }

    func undo() {
        let fm = FileManager.default
        var restored = 0
        let categoryFolders = Set(undoSteps.compactMap { step -> URL? in
            if case .moved(_, let to) = step { return to.deletingLastPathComponent() }
            return nil
        })
        for step in undoSteps.reversed() {
            switch step {
            case .moved(let from, let to):
                if (try? fm.moveItem(at: to, to: from)) != nil { restored += 1 }
            case .trashed(let original, let trashURL):
                if (try? fm.moveItem(at: trashURL, to: original)) != nil { restored += 1 }
            }
        }
        // Remove the category folders Tidy made, but only when nothing at all is left inside.
        for folder in categoryFolders where (try? fm.contentsOfDirectory(atPath: folder.path))?.isEmpty == true {
            try? fm.removeItem(at: folder)
        }
        undoSteps = []
        status = "Put back \(restored) item\(restored == 1 ? "" : "s")."
        Task { await scan() }
    }
}

enum TidyPlanner {
    /// Downloads still in progress — never touch these.
    static let partialExtensions: Set<String> = ["download", "crdownload", "part", "partial", "opdownload"]

    struct LooseFile: Sendable {
        let url: URL
        let category: FileCategory
        let size: Int64
        let modified: Date
        /// When the file landed in this folder (download finished, file dropped in…).
        let added: Date?
        let isPackage: Bool

        /// Where tidying puts this file inside `folder`.
        func destination(in folder: URL) -> URL {
            folder
                .appending(path: category.folderName, directoryHint: .isDirectory)
                .appending(path: url.lastPathComponent)
        }
    }

    /// Files sitting directly in `folder` that tidying would move: no plain folders, hidden files
    /// or downloads still in progress.
    static func looseFiles(in folder: URL) throws -> [LooseFile] {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .isPackageKey, .fileSizeKey, .contentModificationDateKey, .addedToDirectoryDateKey,
        ]
        let items = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])

        var files: [LooseFile] = []
        for url in items {
            let values = try? url.resourceValues(forKeys: keys)
            let isPackage = values?.isPackage ?? false
            // Plain folders (including the category folders we create) stay where they are.
            if values?.isDirectory == true && !isPackage { continue }
            if partialExtensions.contains(url.pathExtension.lowercased()) { continue }
            files.append(LooseFile(
                url: url,
                category: FileCategory.classify(url),
                size: Int64(values?.fileSize ?? 0),
                modified: values?.contentModificationDate ?? .distantPast,
                added: values?.addedToDirectoryDate,
                isPackage: isPackage))
        }
        return files
    }

    static func plan(folder: URL) throws -> [PlannedAction] {
        let candidates = try looseFiles(in: folder)

        // Exact duplicates: same size first (cheap), then same SHA-256. Keep the shortest name,
        // so "report.pdf" survives and "report (1).pdf" goes to the Trash.
        var bySize: [Int64: [Int]] = [:]
        for (i, c) in candidates.enumerated() where c.size > 0 && !c.isPackage {
            bySize[c.size, default: []].append(i)
        }
        var duplicateOf: [Int: String] = [:]
        for indices in bySize.values where indices.count > 1 {
            var seen: [String: Int] = [:]
            let ordered = indices.sorted {
                candidates[$0].url.lastPathComponent.count < candidates[$1].url.lastPathComponent.count
            }
            for i in ordered {
                guard let hash = sha256(of: candidates[i].url) else { continue }
                if let keep = seen[hash] {
                    duplicateOf[i] = candidates[keep].url.lastPathComponent
                } else {
                    seen[hash] = i
                }
            }
        }

        return candidates.enumerated().map { i, c in
            let kind: PlannedAction.Kind
            if let original = duplicateOf[i] {
                kind = .trashDuplicate(of: original)
            } else {
                kind = .move(to: c.destination(in: folder))
            }
            return PlannedAction(source: c.url, kind: kind, category: c.category, size: c.size, modified: c.modified)
        }
        .sorted { ($0.category.rawValue, $0.source.lastPathComponent) < ($1.category.rawValue, $1.source.lastPathComponent) }
    }

    /// "file.pdf" → "file 2.pdf" → "file 3.pdf" … until the name is free.
    static func uniqueURL(for url: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return url }
        let dir = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        for n in 2... {
            let name = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            let candidate = dir.appending(path: name)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
        }
        return url
    }

    static func sha256(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
