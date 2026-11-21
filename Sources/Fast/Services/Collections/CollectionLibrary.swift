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

enum CollectionPropertyType: String, Codable, CaseIterable {
    case text = "Text", number = "Number", date = "Date", select = "Select", multiSelect = "Multi-select", relation = "Relation"

    var symbol: String {
        switch self {
        case .text: "textformat"
        case .number: "number"
        case .date: "calendar"
        case .select: "list.bullet"
        case .multiSelect: "checklist"
        case .relation: "link"
        }
    }
}

struct CollectionProperty: Identifiable, Codable {
    let id: String
    let title: String
    var required = false
    var type = CollectionPropertyType.text
    var numeric: Bool { type == .number }

    init(id: String, title: String, required: Bool = false, type: CollectionPropertyType = .text) {
        self.id = id
        self.title = title
        self.required = required
        self.type = type
    }

    private enum CodingKeys: String, CodingKey { case id, title, required, type }
    private enum LegacyKeys: String, CodingKey { case numeric }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        required = try values.decode(Bool.self, forKey: .required)
        if let saved = try values.decodeIfPresent(CollectionPropertyType.self, forKey: .type) {
            type = saved
        } else {
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            type = try legacy.decodeIfPresent(Bool.self, forKey: .numeric) == true ? .number : .text
        }
    }
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

    private var configuration: (fields: [String], filters: [(String, String)]) {
        switch self {
        case .blank: return ([], [])
        case .contacts: return (["Company", "Status"], [("Active", "Active")])
        case .projects: return (["Owner", "Status"], [("In progress", "In progress")])
        case .tasks: return (["Assignee", "Status"], [("Open", "Open")])
        case .invoices: return (["Client", "Status", "Amount"], [("Outstanding", "Unpaid"), ("Paid", "Paid")])
        }
    }

    var fieldTitles: [String] { configuration.fields }

    func make(name: String) -> PageCollection {
        let (fields, filtered) = configuration
        let primary = CollectionProperty(id: "name", title: name.singularCollectionTitle, required: true)
        let properties = [primary] + fields.map { title in
            let type: CollectionPropertyType = switch title {
            case "Amount": .number
            case "Status": .select
            default: .text
            }
            return CollectionProperty(id: title.lowercased(), title: title, type: type)
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
