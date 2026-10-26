import SwiftUI
import AppKit

struct FolderTidyView: View {
    @Bindable var model: FolderTidyModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding()
            Divider()
            if model.isWorking {
                ProgressView("Looking through \(model.folder.lastPathComponent)…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.actions.isEmpty {
                ContentUnavailableView(
                    model.status ?? "Nothing scanned yet",
                    systemImage: "sparkles",
                    description: Text("Tidy sorts loose files into Screenshots, Images, Documents, Installers and more, and sends exact duplicates to the Trash."))
            } else {
                table
            }
            Divider()
            footer
                .padding(.horizontal)
                .padding(.vertical, 10)
        }
        .navigationTitle("Downloads & Desktop")
        .task(id: model.folder) { await model.scan() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Menu {
                Button("Downloads") { model.folder = .downloadsDirectory }
                Button("Desktop") { model.folder = .desktopDirectory }
                Divider()
                Button("Choose Folder…", action: chooseFolder)
            } label: {
                Label(model.folder.lastPathComponent, systemImage: "folder")
            }
            .fixedSize()

            Button {
                Task { await model.scan() }
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }

            Spacer()

            ForEach(categoryCounts, id: \.0) { name, count in
                Text("\(name) \(count)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
            }
        }
    }

    private var table: some View {
        Table(model.visibleActions) {
            TableColumn("") { action in
                Toggle("", isOn: Binding(
                    get: { model.isIncluded(action.id) },
                    set: { model.setIncluded(action.id, $0) }))
                .labelsHidden()
            }
            .width(24)

            TableColumn("Name") { action in
                HStack(spacing: 6) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: action.source.path))
                        .resizable()
                        .frame(width: 16, height: 16)
                    Text(action.source.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .contextMenu {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([action.source]) }
                }
            }

            TableColumn("Action") { action in
                Text(action.actionLabel)
                    .foregroundStyle(action.isDuplicate ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }
            .width(min: 140, ideal: 220)

            TableColumn("Size") { action in
                Text(action.size.byteString).monospacedDigit()
            }
            .width(80)

            TableColumn("Modified") { action in
                HStack(spacing: 4) {
                    Text(action.modified, format: .dateTime.day().month(.abbreviated).year())
                    if action.isOld {
                        Text("OLD")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .background(.gray, in: RoundedRectangle(cornerRadius: 3))
                    }
                }
            }
            .width(140)
        }
    }

    private var footer: some View {
        HStack {
            Toggle("Only files untouched for 90+ days", isOn: $model.showOnlyOld)
                .toggleStyle(.checkbox)
            Button("Select All") { model.setAll(true) }
            Button("Select None") { model.setAll(false) }
            if let status = model.status, !model.actions.isEmpty {
                Text(status).foregroundStyle(.secondary)
            }
            Spacer()
            if !model.undoSteps.isEmpty {
                Button("Undo", action: model.undo)
            }
            Button("Tidy \(model.includedCount) Item\(model.includedCount == 1 ? "" : "s")", action: model.apply)
                .buttonStyle(.borderedProminent)
                .disabled(model.includedCount == 0)
                .keyboardShortcut(.defaultAction)
        }
    }

    private var categoryCounts: [(String, Int)] {
        var counts: [String: Int] = [:]
        for action in model.actions {
            counts[action.isDuplicate ? "Duplicates" : action.category.rawValue, default: 0] += 1
        }
        return counts.sorted { $0.value > $1.value }.prefix(5).map { ($0.key, $0.value) }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Tidy This Folder"
        if panel.runModal() == .OK, let url = panel.url {
            model.folder = url
        }
    }
}
