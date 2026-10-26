import SwiftUI
import AppKit

struct StorageView: View {
    @Bindable var model: StorageModel
    @State private var pendingTrash: SizedItem?

    var body: some View {
        Group {
            if let report = model.report, !model.isScanning {
                results(report)
            } else if model.isScanning {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Measuring \(model.progress)…").foregroundStyle(.secondary)
                    Button("Stop", action: model.cancel)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView {
                    Label("See what's using your disk", systemImage: "internaldrive")
                } description: {
                    Text("Tidy measures your home folder, finds the biggest files and spots old iPhone backups and caches. Nothing is deleted without asking.")
                } actions: {
                    Button("Scan My Mac", action: model.scan).buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Storage")
        .toolbar {
            if model.report != nil && !model.isScanning {
                Button("Rescan", systemImage: "arrow.clockwise", action: model.scan)
            }
        }
        .confirmationDialog(
            "Move \(pendingTrash?.url.lastPathComponent ?? "") to the Trash?",
            isPresented: Binding(get: { pendingTrash != nil }, set: { if !$0 { pendingTrash = nil } }),
            presenting: pendingTrash
        ) { item in
            Button("Move to Trash (\(item.size.byteString))", role: .destructive) { model.trash(item) }
        } message: { _ in
            Text("You can still restore it from the Trash until you empty it.")
        }
    }

    private func results(_ report: StorageReport) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                diskBar(report)

                if let status = model.status {
                    Text(status).foregroundStyle(.secondary)
                }

                if !report.quickWins.isEmpty {
                    section("Quick wins") {
                        ForEach(report.quickWins) { row($0, max: report.quickWins.map(\.size).max() ?? 1) }
                    }
                }

                section("Home folder") {
                    ForEach(report.folders.prefix(15)) { row($0, max: report.folders.first?.size ?? 1) }
                }

                if !report.largeFiles.isEmpty {
                    section("Largest files (over 200 MB)") {
                        ForEach(report.largeFiles) { row($0, max: report.largeFiles.first?.size ?? 1, showPath: true) }
                    }
                }
            }
            .padding()
            .frame(maxWidth: 900, alignment: .leading)
        }
    }

    private func diskBar(_ report: StorageReport) -> some View {
        let used = report.totalBytes - report.freeBytes
        let fraction = report.totalBytes > 0 ? Double(used) / Double(report.totalBytes) : 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Macintosh HD").font(.headline)
                Spacer()
                Text("\(report.freeBytes.byteString) free of \(report.totalBytes.byteString)")
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: fraction)
                .tint(fraction > 0.9 ? .red : fraction > 0.75 ? .orange : .accentColor)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title3.bold())
            VStack(spacing: 0) { content() }
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func row(_ item: SizedItem, max: Int64, showPath: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                if let note = item.note {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                } else if showPath {
                    Text(item.url.deletingLastPathComponent().path(percentEncoded: false)
                        .replacingOccurrences(of: URL.homeDirectory.path(percentEncoded: false), with: "~/"))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                }
            }
            Spacer(minLength: 12)
            ProgressView(value: Double(item.size), total: Double(Swift.max(max, 1)))
                .frame(width: 120)
            Text(item.size.byteString)
                .monospacedDigit()
                .frame(width: 80, alignment: .trailing)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .help("Show in Finder")
            .buttonStyle(.borderless)
            if showPath && item.canTrash {
                Button {
                    pendingTrash = item
                } label: {
                    Image(systemName: "trash")
                }
                .help("Move to Trash")
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
