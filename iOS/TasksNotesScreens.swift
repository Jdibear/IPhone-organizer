import SwiftUI
import SwiftData

struct TasksScreen: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \TaskItem.createdAt, order: .reverse) private var tasks: [TaskItem]
    @State private var newTitle = ""
    @FocusState private var isAdding: Bool

    private var open: [TaskItem] {
        tasks.filter { !$0.isDone }.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }
    private var completed: [TaskItem] { tasks.filter(\.isDone) }

    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: "plus.circle.fill").foregroundStyle(.tint).font(.title3)
                    TextField("Add a task", text: $newTitle)
                        .focused($isAdding)
                        .submitLabel(.done)
                        .onSubmit(add)
                }
            }

            Section {
                if open.isEmpty {
                    Text("Nothing to do. 🎉").foregroundStyle(.secondary)
                }
                ForEach(open) { TaskRowiOS(task: $0) }
                    .onDelete { $0.map { open[$0] }.forEach(context.delete) }
            }

            if !completed.isEmpty {
                Section("Completed") {
                    ForEach(completed) { TaskRowiOS(task: $0) }
                        .onDelete { $0.map { completed[$0] }.forEach(context.delete) }
                    Button("Clear Completed", role: .destructive) { completed.forEach(context.delete) }
                }
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle("Tasks")
    }

    private func add() {
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        // ✓ on an empty field means "done adding", so put the keyboard away.
        guard !title.isEmpty else {
            isAdding = false
            return
        }
        context.insert(TaskItem(title: title))
        newTitle = ""
        isAdding = true
    }
}

private struct TaskRowiOS: View {
    @Bindable var task: TaskItem

    var body: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation { task.isDone.toggle() }
            } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isDone ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
            .buttonStyle(.plain)

            TextField("Task", text: $task.title, axis: .vertical)
                .strikethrough(task.isDone)
                .foregroundStyle(task.isDone ? .secondary : .primary)

            if let due = task.dueDate {
                Text(due, format: .dateTime.day().month(.abbreviated))
                    .font(.caption)
                    .foregroundStyle(task.isOverdue ? .red : .secondary)
            }
        }
        .contextMenu {
            Button("Due Today", systemImage: "calendar") { task.dueDate = .now }
            Button("Due Tomorrow", systemImage: "calendar") {
                task.dueDate = Calendar.current.date(byAdding: .day, value: 1, to: .now)
            }
            Button("Due Next Week", systemImage: "calendar") {
                task.dueDate = Calendar.current.date(byAdding: .day, value: 7, to: .now)
            }
            if task.dueDate != nil {
                Button("Remove Due Date", systemImage: "calendar.badge.minus") { task.dueDate = nil }
            }
        }
    }
}

struct NotesScreen: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @State private var search = ""
    @State private var path: [Note] = []

    private var filtered: [Note] {
        search.isEmpty ? notes : notes.filter { $0.text.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(filtered) { note in
                    NavigationLink(value: note) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(note.title).lineLimit(1).font(.headline)
                            Text(note.updatedAt, format: .dateTime.day().month(.abbreviated).hour().minute())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { $0.map { filtered[$0] }.forEach(context.delete) }
            }
            .overlay {
                if notes.isEmpty {
                    ContentUnavailableView("No notes yet", systemImage: "note.text",
                                           description: Text("Tap the pencil to write one."))
                }
            }
            .searchable(text: $search)
            .navigationTitle("Notes")
            .navigationDestination(for: Note.self) { NoteEditoriOS(note: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New Note", systemImage: "square.and.pencil") {
                        let note = Note()
                        context.insert(note)
                        path.append(note)
                    }
                }
            }
        }
    }
}

private struct NoteEditoriOS: View {
    @Bindable var note: Note

    var body: some View {
        TextEditor(text: $note.text)
            .padding(.horizontal)
            .navigationTitle(note.title)
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: note.text) { note.updatedAt = .now }
    }
}
