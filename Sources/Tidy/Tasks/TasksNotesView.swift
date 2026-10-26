import SwiftUI
import SwiftData

struct TasksNotesView: View {
    enum Mode: String, CaseIterable { case tasks = "Tasks", notes = "Notes" }
    @State private var mode: Mode = .tasks

    var body: some View {
        Group {
            switch mode {
            case .tasks: TasksView()
            case .notes: NotesView()
            }
        }
        .navigationTitle("Tasks & Notes")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }
    }
}

struct TasksView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \TaskItem.createdAt, order: .reverse) private var tasks: [TaskItem]
    @State private var newTitle = ""
    @State private var newDue: Date?
    @State private var showCompleted = false

    private var open: [TaskItem] {
        tasks.filter { !$0.isDone }.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }
    private var completed: [TaskItem] { tasks.filter(\.isDone) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Add a task and press Return", text: $newTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Menu {
                    Button("Today") { newDue = .now }
                    Button("Tomorrow") { newDue = Calendar.current.date(byAdding: .day, value: 1, to: .now) }
                    Button("Next Week") { newDue = Calendar.current.date(byAdding: .day, value: 7, to: .now) }
                    Divider()
                    Button("No Due Date") { newDue = nil }
                } label: {
                    Label(newDue.map { $0.formatted(.dateTime.day().month(.abbreviated)) } ?? "Due", systemImage: "calendar")
                }
                .fixedSize()
                Button("Add", action: add).disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()

            List {
                if open.isEmpty {
                    Text("Nothing to do. 🎉").foregroundStyle(.secondary)
                }
                ForEach(open) { TaskRow(task: $0) }
                    .onDelete { delete($0.map { open[$0] }) }

                if !completed.isEmpty {
                    Section(isExpanded: $showCompleted) {
                        ForEach(completed) { TaskRow(task: $0) }
                            .onDelete { delete($0.map { completed[$0] }) }
                        Button("Clear Completed", role: .destructive) { delete(completed) }
                    } header: {
                        Text("Completed (\(completed.count))")
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private func add() {
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        context.insert(TaskItem(title: title, dueDate: newDue))
        newTitle = ""
        newDue = nil
    }

    private func delete(_ items: [TaskItem]) {
        items.forEach(context.delete)
    }
}

private struct TaskRow: View {
    @Bindable var task: TaskItem
    @Environment(\.modelContext) private var context

    var body: some View {
        HStack {
            Toggle("", isOn: $task.isDone.animation())
                .toggleStyle(.checkbox)
                .labelsHidden()
            TextField("Task", text: $task.title)
                .textFieldStyle(.plain)
                .strikethrough(task.isDone)
                .foregroundStyle(task.isDone ? .secondary : .primary)
            if let due = task.dueDate {
                Text(due, format: .dateTime.day().month(.abbreviated))
                    .font(.caption)
                    .foregroundStyle(task.isOverdue ? .red : .secondary)
            }
        }
        .contextMenu {
            Button("Due Today") { task.dueDate = .now }
            Button("Due Tomorrow") { task.dueDate = Calendar.current.date(byAdding: .day, value: 1, to: .now) }
            Button("Remove Due Date") { task.dueDate = nil }
            Divider()
            Button("Delete", role: .destructive) { context.delete(task) }
        }
    }
}

struct NotesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @State private var selection: Note?
    @State private var search = ""

    private var filtered: [Note] {
        search.isEmpty ? notes : notes.filter { $0.text.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    TextField("Search", text: $search).textFieldStyle(.roundedBorder)
                    Button(action: newNote) { Image(systemName: "square.and.pencil") }
                        .help("New Note")
                }
                .padding(8)
                List(filtered, selection: $selection) { note in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(note.title).lineLimit(1).bold()
                        Text(note.updatedAt, format: .dateTime.day().month(.abbreviated).hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(note)
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            if selection == note { selection = nil }
                            context.delete(note)
                        }
                    }
                }
            }
            .frame(minWidth: 200, idealWidth: 240, maxWidth: 320)

            Group {
                if let note = selection {
                    NoteEditor(note: note)
                } else {
                    ContentUnavailableView("No note selected", systemImage: "note.text",
                                           description: Text("Pick a note or make a new one."))
                }
            }
            .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func newNote() {
        let note = Note()
        context.insert(note)
        search = ""
        selection = note
    }
}

private struct NoteEditor: View {
    @Bindable var note: Note

    var body: some View {
        TextEditor(text: $note.text)
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding()
            .onChange(of: note.text) { note.updatedAt = .now }
    }
}
