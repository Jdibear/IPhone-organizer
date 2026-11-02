import SwiftUI
import AppKit

struct FolderTidyView: View {
    @Bindable var model: FolderTidyModel
    @Environment(AutoTidyController.self) private var autoTidy

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding()
            Text(explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal)
                .padding(.bottom, 10)
            autoTidyBar
                .padding(.horizontal)
                .padding(.bottom, 10)
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
        .onChange(of: autoTidy.lastSortDate) {
            if model.folder.standardizedFileURL == autoTidy.folder.standardizedFileURL {
                Task { await model.scan() }
            }
        }
    }

    private var autoTidyBar: some View {
        HStack(spacing: 16) {
            AutoTidyToggles()
                .toggleStyle(.switch)
                .controlSize(.small)
            Spacer()
            if let status = autoTidy.status {
                Text(status).font(.caption).foregroundStyle(.red)
            } else if let last = autoTidy.recent.first {
                Text("Last sorted: \(last.to.lastPathComponent) → \(last.category.folderName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else if autoTidy.isEnabled {
                Text("New downloads are sorted as soon as they finish.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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
                Button("Undo") {
                    autoTidy.leaveAlone(model.undoOriginals)
                    model.undo()
                    ActivityLog.shared.add("\(model.status ?? "Put items back.") (Undo in \(model.folder.lastPathComponent))", icon: "arrow.uturn.backward")
                }
            }
            Button("Tidy \(model.includedCount) Item\(model.includedCount == 1 ? "" : "s")") {
                model.apply()
                // Keep apply's own message when something failed, so a failure is never hidden.
                let failed = model.status?.contains("failed") == true
                let result = failed ? (model.status ?? doneSummary) : doneSummary
                model.status = result
                ActivityLog.shared.add(result, icon: "folder.badge.gearshape")
            }
                .buttonStyle(.borderedProminent)
                .disabled(model.includedCount == 0)
                .keyboardShortcut(.defaultAction)
        }
    }

    /// Says up front what the Tidy button is about to do to the ticked files.
    private var explanation: String {
        let included = model.actions.filter(\.included)
        guard !included.isEmpty else {
            return "Tidy sorts the loose files in this folder into subfolders by type. You'll see the plan here before anything moves."
        }
        let duplicates = included.filter(\.isDuplicate).count
        let moves = included.count - duplicates
        var parts: [String] = []
        if moves > 0 { parts.append("move \(moves) file\(moves == 1 ? "" : "s") into subfolders of \(model.folder.lastPathComponent)") }
        if duplicates > 0 { parts.append("send \(duplicates) exact duplicate\(duplicates == 1 ? "" : "s") to the Trash") }
        return "Clicking Tidy will " + parts.joined(separator: " and ") + ". Nothing else changes, and Undo puts it all back."
    }

    /// Says afterwards where everything went, based on what actually moved.
    private var doneSummary: String {
        var folders: [String: Int] = [:]
        var trashed = 0
        for step in model.undoSteps {
            switch step {
            case .moved(_, let to): folders[to.deletingLastPathComponent().lastPathComponent, default: 0] += 1
            case .trashed: trashed += 1
            }
        }
        var parts = folders.sorted { $0.value > $1.value }.map { "\($0.value) to \($0.key)" }
        if trashed > 0 { parts.append("\(trashed) duplicate\(trashed == 1 ? "" : "s") to the Trash") }
        guard !parts.isEmpty else { return model.status ?? "Nothing was moved." }
        return "Tidied \(model.folder.lastPathComponent): moved " + parts.joined(separator: ", ") + "."
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
