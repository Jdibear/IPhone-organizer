import SwiftUI
import Photos
import AppKit

struct PhotosView: View {
    @Bindable var model: PhotosModel
    @State private var previewing: PreviewedAsset?

    var body: some View {
        Group {
            switch model.authorization {
            case .authorized, .limited:
                library
            case .notDetermined:
                ContentUnavailableView {
                    Label("Clean up your photo library", systemImage: "photo.on.rectangle")
                } description: {
                    Text("Tidy finds old screenshots, likely duplicates and long videos. If iCloud Photos is on, cleaning up here cleans up your iPhone too.")
                } actions: {
                    Button("Allow Photos Access") { Task { await model.requestAccess() } }
                        .buttonStyle(.borderedProminent)
                }
            default:
                ContentUnavailableView {
                    Label("Photos access is off", systemImage: "lock")
                } description: {
                    Text("Turn on Tidy in System Settings › Privacy & Security › Photos.")
                } actions: {
                    Button("Open System Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos")!)
                    }
                }
            }
        }
        .navigationTitle("Photos")
        .sheet(item: $previewing) { AssetPreviewSheet(asset: $0.asset, model: model) }
        .task {
            if model.hasAccess && !model.hasLoaded { await model.load() }
        }
    }

    private var library: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $model.section) {
                    ForEach(PhotosModel.Section.allCases) { section in
                        Text("\(section.rawValue) (\(count(section)))").tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
                Button("Select All", action: model.selectAllInSection)
                    .disabled(model.currentAssets.isEmpty)
                Button("Delete \(model.selectedInSection.count) Selected", role: .destructive) {
                    Task {
                        await model.deleteSelected()
                        if let status = model.status, status.hasPrefix("Deleted") {
                            ActivityLog.shared.add(status, icon: "photo")
                        }
                    }
                }
                .disabled(model.selectedInSection.isEmpty)
            }
            .padding()

            Text(model.status ?? summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.bottom, 8)

            Divider()

            if model.isLoading && !model.hasLoaded {
                ProgressView("Reading your library…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.currentAssets.isEmpty {
                ContentUnavailableView("No \(model.section.rawValue.lowercased())", systemImage: "checkmark.circle")
            } else if model.section == .duplicates {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(model.duplicateGroups, id: \.first!.localIdentifier) { group in
                            DuplicateGroupRow(group: group, model: model) { previewing = PreviewedAsset(asset: $0) }
                        }
                    }
                    .padding()
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                        ForEach(model.currentAssets, id: \.localIdentifier) { asset in
                            AssetThumbnail(asset: asset, isSelected: model.selection.contains(asset.localIdentifier))
                                .onTapGesture { model.toggle(asset) }
                                .previewMenu { previewing = PreviewedAsset(asset: asset) }
                        }
                    }
                    .padding()
                }
            }
        }
    }

    private var summary: String {
        if model.section == .duplicates {
            let groups = model.duplicateGroups.count
            return "\(groups) \(groups == 1 ? "set" : "sets") of duplicate photos. The first in each set is the original; "
                + "Select All picks only the copies. Right-click a photo to preview it. Deleted items go to Recently Deleted for 30 days."
        }
        return "Click to select, right-click to preview. Deleted items go to Recently Deleted for 30 days, and sync to your iPhone if iCloud Photos is on."
    }

    private func count(_ section: PhotosModel.Section) -> Int {
        switch section {
        case .screenshots: model.screenshots.count
        case .duplicates: model.duplicates.count
        case .videos: model.videos.count
        }
    }
}

/// One set of duplicate photos side by side, so you can see they really are copies.
private struct DuplicateGroupRow: View {
    let group: [PHAsset]
    let model: PhotosModel
    let onPreview: (PHAsset) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(group.count) identical photos").font(.headline)
                if let date = group.first?.creationDate {
                    Text(date, format: .dateTime.day().month(.abbreviated).year().hour().minute())
                        .foregroundStyle(.secondary)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(group.enumerated()), id: \.element.localIdentifier) { index, asset in
                    AssetThumbnail(asset: asset, isSelected: model.selection.contains(asset.localIdentifier))
                        .overlay(alignment: .bottomLeading) {
                            Text(index == 0 ? "Original" : "Copy \(index)")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(index == 0 ? Color.green : Color.black.opacity(0.55), in: Capsule())
                                .padding(6)
                        }
                        .onTapGesture { model.toggle(asset) }
                        .previewMenu { onPreview(asset) }
                }
            }
            }
        }
    }
}

private struct PreviewedAsset: Identifiable {
    let asset: PHAsset
    var id: String { asset.localIdentifier }
}

private extension View {
    func previewMenu(_ action: @escaping () -> Void) -> some View {
        contextMenu {
            Button("Preview", systemImage: "eye", action: action)
        }
    }
}

/// A big view of a photo or a playing video, so you can check it before deleting it.
private struct AssetPreviewSheet: View {
    let asset: PHAsset
    let model: PhotosModel
    @Environment(\.dismiss) private var dismiss

    private var isSelected: Bool { model.selection.contains(asset.localIdentifier) }

    var body: some View {
        let size = AssetPreviewContent.fittedSize(for: asset, in: CGSize(width: 900, height: 620))
        VStack(spacing: 0) {
            AssetPreviewContent(asset: asset, isInteractive: true)
                .frame(width: max(size.width, 420), height: size.height)
            HStack {
                if let date = asset.creationDate {
                    Text(date, format: .dateTime.day().month(.abbreviated).year().hour().minute())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Select for deleting", isOn: Binding(get: { isSelected }, set: { _ in model.toggle(asset) }))
                    .toggleStyle(.checkbox)
                Button("Close") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
    }
}

struct AssetThumbnail: View {
    let asset: PHAsset
    let isSelected: Bool
    @State private var image: NSImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    Rectangle().fill(.quaternary)
                }
            }
            .frame(width: 120, height: 120)
            .clipped()
            .overlay(alignment: .bottomLeading) {
                if asset.mediaType == .video {
                    Text(Duration.seconds(asset.duration).formatted(.time(pattern: .minuteSecond)))
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
                        .padding(4)
                }
            }

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.8)), isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.black.opacity(0.3)))
                .padding(6)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? Color.accentColor : .clear, lineWidth: 3))
        .contentShape(Rectangle())
        .help(asset.creationDate?.formatted(date: .abbreviated, time: .shortened) ?? "")
        .task(id: asset.localIdentifier) {
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestImage(
                for: asset, targetSize: CGSize(width: 240, height: 240), contentMode: .aspectFill, options: options
            ) { result, _ in
                if let result { image = result }
            }
        }
    }
}
