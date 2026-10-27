import SwiftUI
import Observation

/// iPhone apps can only touch folders you pick in the Files app, so Tidy remembers the one you chose
/// (for example Downloads in iCloud Drive or On My iPhone) with a security-scoped bookmark.
@MainActor
@Observable
final class FolderAccess {
    private static let bookmarkKey = "tidyFolderBookmark"

    private(set) var model: FolderTidyModel?
    var error: String?

    init() {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return }
        var isStale = false
        if let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &isStale) {
            open(url, saveBookmark: isStale)
        }
    }

    func choose(_ url: URL) {
        model?.folder.stopAccessingSecurityScopedResource()
        model = nil
        open(url, saveBookmark: true)
    }

    private func open(_ url: URL, saveBookmark: Bool) {
        guard url.startAccessingSecurityScopedResource() else {
            error = "Tidy couldn't open \(url.lastPathComponent). Choose it again."
            return
        }
        if saveBookmark, let data = try? url.bookmarkData() {
            UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
        }
        error = nil
        model = FolderTidyModel(folder: url)
    }
}

struct FilesScreen: View {
    let access: FolderAccess
    @State private var isPicking = false

    var body: some View {
        Group {
            if let model = access.model {
                FolderPlanList(model: model)
            } else {
                ContentUnavailableView {
                    Label("Tidy a folder", systemImage: "folder.badge.gearshape")
                } description: {
                    Text(access.error ?? "Pick a messy folder, like Downloads in iCloud Drive. Tidy sorts its files into Images, Documents, Videos and more, and finds exact duplicates.")
                } actions: {
                    Button("Choose Folder") { isPicking = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle(access.model?.folder.lastPathComponent ?? "Files")
        .toolbar {
            if access.model != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Change Folder", systemImage: "folder") { isPicking = true }
                }
            }
        }
        .fileImporter(isPresented: $isPicking, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { access.choose(url) }
        }
    }
}

private struct FolderPlanList: View {
    @Bindable var model: FolderTidyModel

    var body: some View {
        List {
            if let status = model.status, !model.actions.isEmpty {
                Text(status).font(.footnote).foregroundStyle(.secondary)
            }
            if model.isWorking {
                HStack { ProgressView(); Text("Looking through \(model.folder.lastPathComponent)…") }
            }
            ForEach(model.visibleActions) { action in
                Button {
                    model.setIncluded(action.id, !action.included)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: action.included ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(action.included ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                            .font(.title3)
                        Image(systemName: action.category.symbol)
                            .frame(width: 24)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(action.source.lastPathComponent)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(.primary)
                            HStack(spacing: 6) {
                                Text(action.actionLabel)
                                    .foregroundStyle(action.isDuplicate ? .orange : .secondary)
                                Text("· \(action.size.byteString)")
                                    .foregroundStyle(.secondary)
                                if action.isOld {
                                    Text("OLD").font(.caption2.bold()).foregroundStyle(.secondary)
                                }
                            }
                            .font(.caption)
                            .lineLimit(1)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .overlay {
            if !model.isWorking && model.actions.isEmpty {
                ContentUnavailableView(model.status ?? "Nothing to tidy", systemImage: "sparkles")
            }
        }
        .refreshable { await model.scan() }
        .task(id: model.folder) { await model.scan() }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button("Select All") { model.setAll(true) }
                    Button("Select None") { model.setAll(false) }
                    Toggle("Only Old Files", isOn: $model.showOnlyOld)
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                if !model.undoSteps.isEmpty {
                    Button("Undo", action: model.undo)
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                }
                Button {
                    model.apply()
                } label: {
                    Text("Tidy \(model.includedCount) Item\(model.includedCount == 1 ? "" : "s")")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.includedCount == 0)
            }
            .padding()
            .background(.bar)
        }
    }
}

extension FileCategory {
    var symbol: String {
        switch self {
        case .screenshots: "camera.viewfinder"
        case .images: "photo"
        case .documents: "doc.text"
        case .archives: "archivebox"
        case .installers: "shippingbox"
        case .videos: "film"
        case .audio: "music.note"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .other: "questionmark.folder"
        }
    }
}
