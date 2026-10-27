import SwiftUI
import Photos
import UIKit

struct PhotosScreen: View {
    @Bindable var model: PhotosModel
    @Environment(\.openURL) private var openURL

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

                Text(model.status ?? "\(model.currentAssets.count) found. Tap to select. Deleted items stay in Recently Deleted for 30 days.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if model.isLoading && !model.hasLoaded {
                    ProgressView("Reading your library…").frame(maxWidth: .infinity).padding(.top, 40)
                } else if model.currentAssets.isEmpty {
                    ContentUnavailableView("Nothing here", systemImage: "checkmark.circle")
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 3)], spacing: 3) {
                        ForEach(model.currentAssets, id: \.localIdentifier) { asset in
                            PhotoThumbnail(asset: asset, isSelected: model.selection.contains(asset.localIdentifier))
                                .onTapGesture { model.toggle(asset) }
                        }
                    }
                }
            }
            .padding()
        }
        .refreshable { await model.load() }
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
