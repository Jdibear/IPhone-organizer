import SwiftUI
import AppKit

struct CleanupView: View {
    @Bindable var model: CleanupModel
    @State private var isConfirming = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Frees up space by removing files your Mac doesn't need.")
                    .font(.headline)
                Text("Tick what you want removed, then click Clean Up. Your documents, photos and apps aren't touched.")
                    .foregroundStyle(.secondary)
            }
            .padding()

            if let result = model.result {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(result)
                    Spacer()
                    if model.movedToTrash {
                        Button("Open Trash") {
                            NSWorkspace.shared.open(URL.homeDirectory.appending(path: ".Trash"))
                        }
                    }
                }
                .padding(10)
                .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal)
                .padding(.bottom, 10)
            }

            Divider()

            if model.isCleaning {
                ProgressView("Cleaning up…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.isScanning && !model.hasScanned {
                ProgressView("Looking for files you don't need…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.targets.isEmpty {
                ContentUnavailableView("Nothing to clean up", systemImage: "checkmark.circle",
                                       description: Text("Your Mac has no caches or leftovers worth removing right now."))
            } else {
                List(model.targets) { target in
                    row(target)
                }
            }

            Divider()

            HStack {
                Text("Quit other apps first to clear more of their caches.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clean Up \(model.selectedSize.byteString)") { isConfirming = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.selected.isEmpty || model.isCleaning || model.isScanning)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .navigationTitle("Clean Up")
        .toolbar {
            Button("Rescan", systemImage: "arrow.clockwise") { Task { await model.scan() } }
                .disabled(model.isScanning || model.isCleaning)
        }
        .task { if !model.hasScanned { await model.scan() } }
        .confirmationDialog("Clean up \(model.selectedSize.byteString)?", isPresented: $isConfirming) {
            Button("Clean Up", role: .destructive) { Task { await model.cleanSelected() } }
        } message: {
            Text(confirmationText)
        }
    }

    private var confirmationText: String {
        let deleted = model.selectedTargets.filter { $0.method == .delete }.map(\.title)
        let trashed = model.selectedTargets.filter { $0.method == .trash }.map(\.title)
        var lines: [String] = []
        if !deleted.isEmpty { lines.append("Deleted for good (apps rebuild these): \(deleted.joined(separator: ", ")).") }
        if !trashed.isEmpty { lines.append("Moved to the Trash: \(trashed.joined(separator: ", ")).") }
        return lines.joined(separator: "\n")
    }

    private func row(_ target: CleanupTarget) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle("", isOn: Binding(
                get: { model.selected.contains(target.id) },
                set: { if $0 { model.selected.insert(target.id) } else { model.selected.remove(target.id) } }))
            .labelsHidden()
            Image(systemName: target.icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(target.title).font(.headline)
                Text(target.explanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if target.method == .trash {
                    Text(target.entries.map(\.lastPathComponent).joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            Spacer(minLength: 12)
            Text(target.size.byteString)
                .monospacedDigit()
                .fontWeight(.medium)
        }
        .padding(.vertical, 4)
    }
}
