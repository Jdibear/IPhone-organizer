import SwiftUI
import Photos
import UIKit

struct PhotosScreen: View {
    @Bindable var model: PhotosModel
    @Environment(\.openURL) private var openURL
    @State private var fullScreen: FullScreenAsset?

    var body: some View {
        Group {
            switch model.authorization {
            case .authorized, .limited:
                library
            case .notDetermined:
                ContentUnavailableView {
                    Label("Clean up your photos", systemImage: "photo.on.rectangle")
                } description: {
                    Text("Tidy finds old screenshots, likely duplicates and long videos so you can free up space.")
                } actions: {
                    Button("Allow Photos Access") { Task { await model.requestAccess() } }
                        .buttonStyle(.borderedProminent)
                }
            default:
                ContentUnavailableView {
                    Label("Photos access is off", systemImage: "lock")
                } description: {
                    Text("Turn it on in Settings › Apps › Tidy › Photos.")
                } actions: {
                    Button("Open Settings") { openURL(URL(string: UIApplication.openSettingsURLString)!) }
                }
            }
        }
        .navigationTitle("Photos")
        .task {
            if model.hasAccess && !model.hasLoaded { await model.load() }
        }
    }

    private var library: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let free = freeSpace {
                    Label("\(free.byteString) free on this iPhone", systemImage: "internaldrive")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Picker("Section", selection: $model.section) {
                    ForEach(PhotosModel.Section.allCases) { section in
                        Text(shortName(section)).tag(section)
                    }
                }
                .pickerStyle(.segmented)

                Text(model.status ?? summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if model.isLoading && !model.hasLoaded {
                    ProgressView("Reading your library…").frame(maxWidth: .infinity).padding(.top, 40)
                } else if model.currentAssets.isEmpty {
                    ContentUnavailableView("Nothing here", systemImage: "checkmark.circle")
                } else if model.section == .duplicates {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(model.duplicateGroups, id: \.first!.localIdentifier) { group in
                            DuplicateGroupRow(group: group, model: model) { fullScreen = FullScreenAsset(asset: $0) }
                        }
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 3)], spacing: 3) {
                        ForEach(model.currentAssets, id: \.localIdentifier) { asset in
                            PhotoThumbnail(asset: asset, isSelected: model.selection.contains(asset.localIdentifier))
                                .onTapGesture { model.toggle(asset) }
                                .holdToPreview(asset, model: model) { fullScreen = FullScreenAsset(asset: $0) }
                        }
                    }
                }
            }
            .padding()
        }
        .refreshable { await model.load() }
        .fullScreenCover(item: $fullScreen) { AssetFullScreenView(asset: $0.asset, model: model) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Select All", action: model.selectAllInSection)
                    .disabled(model.currentAssets.isEmpty)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !model.selectedInSection.isEmpty {
                Button(role: .destructive) {
                    Task { await model.deleteSelected() }
                } label: {
                    Label("Delete \(model.selectedInSection.count)", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
                .padding()
                .background(.bar)
            }
        }
    }

    private var summary: String {
        if model.section == .duplicates {
            let groups = model.duplicateGroups.count
            return "\(groups) \(groups == 1 ? "set" : "sets") of duplicate photos, \(model.duplicates.count) extra \(model.duplicates.count == 1 ? "copy" : "copies"). "
                + "The first photo in each set is the original; Select All picks only the copies. Hold a photo to see it bigger."
        }
        return "\(model.currentAssets.count) found. Tap to select, hold to see it bigger. Deleted items stay in Recently Deleted for 30 days."
    }

    private func shortName(_ section: PhotosModel.Section) -> String {
        switch section {
        case .screenshots: "Screenshots"
        case .duplicates: "Duplicates"
        case .videos: "Videos"
        }
    }

    private var freeSpace: Int64? {
        try? URL.homeDirectory
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
    }
}

/// One set of duplicate photos side by side, so you can see they really are copies.
private struct DuplicateGroupRow: View {
    let group: [PHAsset]
    let model: PhotosModel
    let onViewFullScreen: (PHAsset) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(group.count) identical photos").font(.subheadline.bold())
                if let date = group.first?.creationDate {
                    Text(date, format: .dateTime.day().month(.abbreviated).year().hour().minute())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(group.enumerated()), id: \.element.localIdentifier) { index, asset in
                        PhotoThumbnail(asset: asset, isSelected: model.selection.contains(asset.localIdentifier))
                            .frame(width: 110)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(alignment: .bottomLeading) {
                                Text(index == 0 ? "Original" : "Copy \(index)")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(index == 0 ? Color.green : Color.black.opacity(0.55), in: Capsule())
                                    .padding(5)
                            }
                            .onTapGesture { model.toggle(asset) }
                            .holdToPreview(asset, model: model, onViewFullScreen: onViewFullScreen)
                    }
                }
            }
        }
    }
}

private struct FullScreenAsset: Identifiable {
    let asset: PHAsset
    var id: String { asset.localIdentifier }
}

private extension View {
    /// Hold a photo to see it bigger, or a video to watch it play. Letting go keeps it open until you tap away.
    func holdToPreview(_ asset: PHAsset, model: PhotosModel, onViewFullScreen: @escaping (PHAsset) -> Void) -> some View {
        contextMenu {
            Button(model.selection.contains(asset.localIdentifier) ? "Deselect" : "Select for Deleting",
                   systemImage: "checkmark.circle") {
                model.toggle(asset)
            }
            Button("View Full Screen", systemImage: "arrow.up.left.and.arrow.down.right") {
                onViewFullScreen(asset)
            }
        } preview: {
            let size = AssetPreviewContent.fittedSize(for: asset, in: CGSize(width: 350, height: 520))
            AssetPreviewContent(asset: asset)
                .frame(width: size.width, height: size.height)
        }
    }
}

/// Full-size view with playback controls for videos, and pinch or double-tap to zoom for photos.
private struct AssetFullScreenView: View {
    let asset: PHAsset
    let model: PhotosModel
    @Environment(\.dismiss) private var dismiss

    private var isSelected: Bool { model.selection.contains(asset.localIdentifier) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            AssetPreviewContent(asset: asset, isInteractive: true)
        }
        .safeAreaInset(edge: .top) {
            HStack {
                if let date = asset.creationDate {
                    Text(date, format: .dateTime.day().month(.abbreviated).year().hour().minute())
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.8))
                }
                Spacer()
                Button("Close", systemImage: "xmark.circle.fill") { dismiss() }
                    .labelStyle(.iconOnly)
                    .font(.title)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal)
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                model.toggle(asset)
            } label: {
                Label(isSelected ? "Selected for Deleting" : "Select for Deleting",
                      systemImage: isSelected ? "checkmark.circle.fill" : "circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(isSelected ? .red : .gray)
            .controlSize(.large)
            .padding()
        }
    }
}

struct PhotoThumbnail: View {
    let asset: PHAsset
    let isSelected: Bool
    @State private var image: UIImage?

    var body: some View {
        Color.secondary.opacity(0.15)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .clipped()
            .overlay(alignment: .bottomLeading) {
                if asset.mediaType == .video {
                    Text(Duration.seconds(asset.duration).formatted(.time(pattern: .minuteSecond)))
                        .font(.caption2.bold().monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
                        .padding(4)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white, .tint)
                        .padding(5)
                }
            }
            .overlay {
                if isSelected { Rectangle().stroke(Color.accentColor, lineWidth: 3) }
            }
            .contentShape(Rectangle())
            .task(id: asset.localIdentifier) {
                let options = PHImageRequestOptions()
                options.deliveryMode = .opportunistic
                options.isNetworkAccessAllowed = true
                PHImageManager.default().requestImage(
                    for: asset, targetSize: CGSize(width: 300, height: 300), contentMode: .aspectFill, options: options
                ) { result, _ in
                    if let result { image = result }
                }
            }
    }
}
