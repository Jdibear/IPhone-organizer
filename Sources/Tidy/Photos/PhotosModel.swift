import Foundation
import Observation
import Photos

@MainActor
@Observable
final class PhotosModel {
    enum Section: String, CaseIterable, Identifiable {
        case screenshots = "Screenshots"
        case duplicates = "Likely Duplicates"
        case videos = "Longest Videos"
        var id: Self { self }
    }

    var authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    var section: Section = .screenshots
    var screenshots: [PHAsset] = []
    /// Extra copies only — the first photo of each duplicate group is kept out of this list.
    var duplicates: [PHAsset] = []
    var videos: [PHAsset] = []
    var selection: Set<String> = []
    var isLoading = false
    var hasLoaded = false
    var status: String?

    var hasAccess: Bool { authorization == .authorized || authorization == .limited }

    var currentAssets: [PHAsset] {
        switch section {
        case .screenshots: screenshots
        case .duplicates: duplicates
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
        duplicates = dupes
        videos = vids
        selection = selection.intersection(Set((shots + dupes + vids).map(\.localIdentifier)))
        isLoading = false
        hasLoaded = true
    }

    func toggle(_ asset: PHAsset) {
        if selection.remove(asset.localIdentifier) == nil { selection.insert(asset.localIdentifier) }
    }

    func selectAllInSection() {
        selection.formUnion(currentAssets.map(\.localIdentifier))
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
            status = "Deleted \(assets.count) item\(assets.count == 1 ? "" : "s"). They're in Recently Deleted for 30 days."
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

    /// Photos taken in the same second with the same dimensions are almost always copies
    /// (re-imports, saved twice from a chat, etc.).
    nonisolated private static func fetchDuplicates() -> [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        var seen = Set<String>()
        var extras: [PHAsset] = []
        PHAsset.fetchAssets(with: .image, options: options).enumerateObjects { asset, _, _ in
            guard let date = asset.creationDate, asset.burstIdentifier == nil else { return }
            let key = "\(Int(date.timeIntervalSince1970))-\(asset.pixelWidth)x\(asset.pixelHeight)"
            if !seen.insert(key).inserted { extras.append(asset) }
        }
        return extras
    }

    nonisolated private static func assets(_ result: PHFetchResult<PHAsset>) -> [PHAsset] {
        var list: [PHAsset] = []
        list.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in list.append(asset) }
        return list
    }
}
