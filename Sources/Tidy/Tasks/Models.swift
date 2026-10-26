import Foundation
import SwiftData

// Every property has a default so these models can sync with CloudKit later (iPhone companion).

@Model
final class TaskItem {
    var title: String = ""
    var isDone: Bool = false
    var dueDate: Date?
    var createdAt: Date = Date.now

    init(title: String, dueDate: Date? = nil) {
        self.title = title
        self.dueDate = dueDate
    }

    var isOverdue: Bool {
        guard let dueDate, !isDone else { return false }
        return dueDate < Calendar.current.startOfDay(for: .now)
    }
}

@Model
final class Note {
    var text: String = ""
    var updatedAt: Date = Date.now

    init(text: String = "") {
        self.text = text
    }

    var title: String {
        let firstLine = text.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
        return firstLine.trimmingCharacters(in: .whitespaces).isEmpty ? "New Note" : firstLine
    }
}
