import Foundation
import Observation
import Photos

@MainActor
@Observable
final class PhotosModel {
    enum Section: String, CaseIterable, Identifiable {
        case screenshots = "Screenshots"
        case duplicates = "Duplicates"
        case videos = "Longest Videos"
        var id: Self { self }
    }

    var authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    var section: Section = .screenshots
    var screenshots: [PHAsset] = []
    /// Each group holds photos that look like copies of each other; the first one is the original to keep.
    var duplicateGroups: [[PHAsset]] = []
    /// Extra copies only — the original of each group is left out.
    var duplicates: [PHAsset] { duplicateGroups.flatMap { $0.dropFirst() } }
    var videos: [PHAsset] = []
    var selection: Set<String> = []
    var isLoading = false
    var hasLoaded = false
    var status: String?

    var hasAccess: Bool { authorization == .authorized || authorization == .limited }

    var currentAssets: [PHAsset] {
        switch section {
        case .screenshots: screenshots
        case .duplicates: duplicateGroups.flatMap { $0 }
        case .videos: videos
        }
    }

    var selectedInSection: [PHAsset] {
        currentAssets.filter { selection.contains($0.localIdentifier) }
    }

    func requestAccess() async {
        authorization = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        if hasAccess { await load() }
    }

    func load() async {
        guard hasAccess else { return }
        isLoading = true
        let (shots, dupes, vids) = await Task.detached(priority: .userInitiated) {
            (Self.fetchScreenshots(), Self.fetchDuplicates(), Self.fetchVideos())
        }.value
        screenshots = shots
        duplicateGroups = dupes
        videos = vids
        selection = selection.intersection(Set((shots + dupes.flatMap { $0 } + vids).map(\.localIdentifier)))
        isLoading = false
        hasLoaded = true
    }

    func toggle(_ asset: PHAsset) {
        if selection.remove(asset.localIdentifier) == nil { selection.insert(asset.localIdentifier) }
    }

    func selectAllInSection() {
        // For duplicates, only the extra copies — never the original of a group.
        let assets = section == .duplicates ? duplicates : currentAssets
        selection.formUnion(assets.map(\.localIdentifier))
    }

    func deleteSelected() async {
        let assets = selectedInSection
        guard !assets.isEmpty else { return }
        do {
            // macOS shows its own confirmation; deleted items sit in Recently Deleted for 30 days.
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets as NSArray)
            }
            selection.subtract(assets.map(\.localIdentifier))
            status = assets.count == 1
                ? "Deleted 1 item. It's in Recently Deleted for 30 days."
                : "Deleted \(assets.count) items. They're in Recently Deleted for 30 days."
            await load()
        } catch {
            status = "Nothing was deleted."
        }
    }

    nonisolated private static func fetchScreenshots() -> [PHAsset] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "(mediaSubtypes & %d) != 0", PHAssetMediaSubtype.photoScreenshot.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        return assets(PHAsset.fetchAssets(with: .image, options: options))
    }

    nonisolated private static func fetchVideos() -> [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "duration", ascending: false)]
        options.fetchLimit = 200
        return assets(PHAsset.fetchAssets(with: .video, options: options))
    }

    /// Copies from re-imports or saving twice from a chat share a timestamp and size, so those are
    /// the candidates; `PhotoMatcher` then drops shots that only look alike.
    nonisolated private static func fetchDuplicates() -> [[PHAsset]] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        var groups: [String: [PHAsset]] = [:]
        var order: [String] = []
        PHAsset.fetchAssets(with: .image, options: options).enumerateObjects { asset, _, _ in
            guard let date = asset.creationDate, asset.burstIdentifier == nil else { return }
            let key = "\(Int(date.timeIntervalSince1970))-\(asset.pixelWidth)x\(asset.pixelHeight)"
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(asset)
        }
        // Same second and size only makes them candidates; keep the ones whose pixels actually match.
        return order.compactMap { groups[$0] }.filter { $0.count > 1 }.flatMap { candidates in
            PhotoMatcher.copySets(candidates.map(PhotoMatcher.fingerprint(of:))).map { $0.map { candidates[$0] } }
        }
    }

    nonisolated private static func assets(_ result: PHFetchResult<PHAsset>) -> [PHAsset] {
        var list: [PHAsset] = []
        list.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in list.append(asset) }
        return list
    }
}
