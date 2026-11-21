import Foundation
import Observation

enum CollectionCalculation: String, Codable, CaseIterable {
    case count, unique, sum, average, minimum, maximum

    func result(_ values: [String]) -> String {
        let filled = values.filter { !$0.isEmpty }
        let numbers = filled.compactMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) }
        let total = numbers.reduce(0, +)
        switch self {
        case .count: return String(filled.count)
        case .unique: return String(Set(filled).count)
        case .sum: return total.formatted()
        case .average: return numbers.isEmpty ? "—" : (total / Decimal(numbers.count)).formatted()
        case .minimum: return numbers.min()?.formatted() ?? "—"
        case .maximum: return numbers.max()?.formatted() ?? "—"
        }
    }
}

struct CollectionProperty: Identifiable, Codable {
    let id: String
    let title: String
    var required = false
    var numeric = false
}

struct CollectionEntry: Identifiable, Codable {
    var id = UUID()
    var values: [String: String]
}

struct CollectionFilter: Identifiable, Equatable, Codable {
    var id = UUID()
    let property: String
    let value: String
}

struct CollectionTableView: Identifiable, Codable {
    var id = UUID()
    var name: String
    var filters: [CollectionFilter] = []
    var calculations: [String: CollectionCalculation] = [:]
    var hidden: Set<String> = []
    var pageSize = 25
    var sortProperty: String?
    var descending: Bool?

    func records(in collection: PageCollection, including current: UUID? = nil) -> [CollectionEntry] {
        let filtered = collection.entries.filter { $0.id == current || matches($0) }
        guard let sortProperty, let property = collection.properties.first(where: { $0.id == sortProperty }) else { return filtered }
        return filtered.sorted { lhs, rhs in
            let left = lhs.values[sortProperty] ?? ""
            let right = rhs.values[sortProperty] ?? ""
            let order: ComparisonResult
            if property.numeric, let a = Decimal(string: left), let b = Decimal(string: right) {
                order = NSDecimalNumber(decimal: a).compare(NSDecimalNumber(decimal: b))
            } else {
                order = left.localizedStandardCompare(right)
            }
            return descending == true ? order == .orderedDescending : order == .orderedAscending
        }
    }

    func matches(_ entry: CollectionEntry) -> Bool {
        filters.allSatisfy { entry.values[$0.property]?.localizedCaseInsensitiveCompare($0.value) == .orderedSame }
    }
}

struct PageCollection: Identifiable, Codable {
    var id = UUID()
    var name: String
    var symbol: String
    var properties: [CollectionProperty]
    var views: [CollectionTableView]
    var sourceTemplate: CollectionTemplate?
    var recordTemplate: RecordTemplate?
    var selectedView: UUID?
    var entries: [CollectionEntry] = []
}

enum CollectionTemplate: String, CaseIterable, Codable {
    case blank = "Blank", contacts = "Contacts", projects = "Projects", tasks = "Tasks", invoices = "Invoices"

    var symbol: String {
        switch self {
        case .blank: return "tablecells"
        case .contacts: return "person.2"
        case .projects: return "folder"
        case .tasks: return "checklist"
        case .invoices: return "doc.text"
        }
    }

    func make(name: String) -> PageCollection {
        let fields: [String]
        let filtered: [(String, String)]
        switch self {
        case .blank: fields = []; filtered = []
        case .contacts: fields = ["Company", "Status"]; filtered = [("Active", "Active")]
        case .projects: fields = ["Owner", "Status"]; filtered = [("In progress", "In progress")]
        case .tasks: fields = ["Assignee", "Status"]; filtered = [("Open", "Open")]
        case .invoices: fields = ["Client", "Status", "Amount"]; filtered = [("Outstanding", "Unpaid"), ("Paid", "Paid")]
        }
        let properties = ([name.singularCollectionTitle] + fields).enumerated().map { index, title in
            CollectionProperty(id: index == 0 ? "name" : title.lowercased(), title: title, required: index == 0, numeric: index > 0 && title == "Amount")
        }
        var views = [CollectionTableView(name: "All " + name.lowercased())]
        views += filtered.map { CollectionTableView(name: $0.0, filters: [CollectionFilter(property: "status", value: $0.1)]) }
        return PageCollection(name: name, symbol: symbol, properties: properties, views: views, sourceTemplate: self)
    }
}

private extension String {
    var singularCollectionTitle: String {
        if lowercased().hasSuffix("ies"), count > 3 { return String(dropLast(3)) + "y" }
        if lowercased().hasSuffix("s"), !lowercased().hasSuffix("ss"), count > 1 { return String(dropLast()) }
        return self
    }
}

@MainActor @Observable
final class CollectionLibrary {
    static let shared = CollectionLibrary()
    private let settings: UserDefaults
    private let key = "collections.library.v1"
    var collections: [PageCollection] {
        didSet { if let data = try? JSONEncoder().encode(collections) { settings.set(data, forKey: key) } }
    }

    init(settings: UserDefaults = Store.settings) {
        self.settings = settings
        collections = settings.data(forKey: key).flatMap { try? JSONDecoder().decode([PageCollection].self, from: $0) }
            ?? [CollectionTemplate.invoices.make(name: "Invoices")]
    }
}
