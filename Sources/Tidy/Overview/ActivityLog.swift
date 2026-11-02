import Foundation
import Observation

struct ActivityEntry: Codable, Identifiable {
    var id = UUID()
    var date = Date.now
    let text: String
    let icon: String
}

/// A plain-language history of what Tidy has done, shown on the Overview screen. Kept between launches.
@MainActor
@Observable
final class ActivityLog {
    static let shared = ActivityLog()
    private static let key = "tidyActivity"

    private(set) var entries: [ActivityEntry]

    private init() {
        let saved = UserDefaults.standard.data(forKey: Self.key)
        entries = saved.flatMap { try? JSONDecoder().decode([ActivityEntry].self, from: $0) } ?? []
    }

    func add(_ text: String, icon: String) {
        entries = Array(([ActivityEntry(text: text, icon: icon)] + entries).prefix(50))
        UserDefaults.standard.set(try? JSONEncoder().encode(entries), forKey: Self.key)
    }
}
