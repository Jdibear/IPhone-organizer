import SwiftUI
import AppKit

struct AppsView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case category = "By Type"
        case unused = "Not Used Lately"
        case largest = "Largest"
        var id: Self { self }
    }

    @Bindable var model: AppsModel
    @State private var mode = Mode.category
    @State private var pendingTrash: AppInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Shows every app you have, sorted by what it's for.")
                    .font(.headline)
                Text("Spot big apps and ones you've stopped using, and remove them. Apps stay where they are unless you choose otherwise, so they keep updating normally.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()

            Picker("", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.horizontal)
            .padding(.bottom, 10)

            if let status = model.status {
                Text(status)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 10)
            }

            Divider()

            if model.isScanning && !model.hasScanned {
                ProgressView("Looking through your apps…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list
            }
        }
        .navigationTitle("Apps")
        .toolbar {
            Button("Rescan", systemImage: "arrow.clockwise") { Task { await model.scan() } }
                .disabled(model.isScanning)
        }
        .task { if !model.hasScanned { await model.scan() } }
        .confirmationDialog(
            "Move \(pendingTrash?.name ?? "") to the Trash?",
            isPresented: Binding(get: { pendingTrash != nil }, set: { if !$0 { pendingTrash = nil } }),
            presenting: pendingTrash
        ) { app in
            Button("Move to Trash", role: .destructive) { model.trash(app) }
        } message: { _ in
            Text("You can put it back from the Trash until you empty it. Its settings and documents stay on your Mac.")
        }
    }

    private var list: some View {
        List {
            if !model.strays.isEmpty {
                Section("Not in your Applications folder") {
                    ForEach(model.strays) { app in
                        row(app) {
                            Button("Move to Applications") { model.moveToApplications(app) }
                        }
                    }
                }
            }
            switch mode {
            case .category:
                ForEach(model.groups, id: \.name) { group in
                    Section("\(group.name) (\(group.apps.count))") {
                        ForEach(group.apps) { app in row(app) }
                    }
                }
            case .unused:
                Section("Not opened in the last 6 months (\(model.unused.count))") {
                    if model.unused.isEmpty {
                        Text("You've used all your apps recently, as far as your Mac knows.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.unused) { app in row(app) }
                }
            case .largest:
                Section("Biggest first") {
                    ForEach(model.largest) { app in row(app) }
                }
            }
        }
    }

    private func row(_ app: AppInfo) -> some View {
        row(app) { EmptyView() }
    }

    private func row<Extra: View>(_ app: AppInfo, @ViewBuilder extra: () -> Extra) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                .resizable()
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).lineLimit(1)
                Text(lastUsedText(app))
                    .font(.caption)
                    .foregroundStyle(app.isUnused ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
            }
            Spacer(minLength: 12)
            extra()
            Text(app.size?.byteString ?? "…")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([app.url])
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .help("Show in Finder")
            .buttonStyle(.borderless)
            Button {
                pendingTrash = app
            } label: {
                Image(systemName: "trash")
            }
            .help(removeHelp(app))
            .buttonStyle(.borderless)
            .disabled(app.isSystem || model.isRunning(app))
        }
    }

    private func removeHelp(_ app: AppInfo) -> String {
        if app.isSystem { return "This app is part of macOS and can't be removed." }
        if model.isRunning(app) { return "Quit this app before removing it." }
        return "Move to Trash"
    }

    private func lastUsedText(_ app: AppInfo) -> String {
        if app.isSystem { return "Part of macOS" }
        guard let lastUsed = app.lastUsed else { return "Last opened: unknown" }
        return "Last opened \(lastUsed.formatted(.relative(presentation: .named)))"
    }
}
