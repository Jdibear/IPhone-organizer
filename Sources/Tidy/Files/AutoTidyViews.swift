import SwiftUI
import AppKit

/// Toggles shared by the menu bar and the Downloads & Desktop screen.
struct AutoTidyToggles: View {
    @Environment(AutoTidyController.self) private var autoTidy

    var body: some View {
        @Bindable var autoTidy = autoTidy
        Toggle("Sort new downloads automatically", isOn: $autoTidy.isEnabled)
        Toggle("Open Tidy at login", isOn: Binding(
            get: { autoTidy.opensAtLogin },
            set: { autoTidy.setOpensAtLogin($0) }))
    }
}

struct AutoTidyEventRow: View {
    let event: AutoTidyEvent
    @Environment(AutoTidyController.self) private var autoTidy

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: event.to.path))
                .resizable()
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.to.lastPathComponent).lineLimit(1).truncationMode(.middle)
                Text("→ \(event.category.folderName) · \(event.date.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([event.to])
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .help("Show in Finder")
            Button("Undo") { autoTidy.undo(event) }
        }
        .buttonStyle(.borderless)
    }
}

struct AutoTidyMenu: View {
    @Environment(AutoTidyController.self) private var autoTidy
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tidy").font(.headline)
            AutoTidyToggles()
                .toggleStyle(.switch)
                .controlSize(.small)

            if let status = autoTidy.status {
                Text(status).font(.caption).foregroundStyle(.red)
            }

            Divider()

            if autoTidy.recent.isEmpty {
                Text(autoTidy.isEnabled ? "Waiting for new downloads…" : "Automatic sorting is off.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("Recently sorted").font(.caption.bold()).foregroundStyle(.secondary)
                ForEach(autoTidy.recent.prefix(6)) { AutoTidyEventRow(event: $0) }
            }

            Divider()

            HStack {
                Button("Open Tidy") {
                    openWindow(id: "main")
                    NSApp.activate()
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding()
        .frame(width: 320)
    }
}
