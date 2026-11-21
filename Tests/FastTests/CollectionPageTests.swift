import Foundation
import Testing
@testable import Fast

@Suite @MainActor
struct CollectionPageTests {
    @Test func propertyTypesPreserveLegacyNumbersAndRoundTripNewFields() throws {
        let legacy = Data(#"{"id":"old-field","title":"Budget","numeric":true,"required":true}"#.utf8)
        let field = try JSONDecoder().decode(CollectionProperty.self, from: legacy)
        #expect(field.type == .number)
        #expect(field.required)
        let fields = CollectionPropertyType.allCases.map {
            CollectionProperty(id: UUID().uuidString, title: $0.rawValue, required: true, type: $0)
        }
        let saved = try JSONDecoder().decode([CollectionProperty].self, from: JSONEncoder().encode(fields))
        #expect(saved.map(\.type) == CollectionPropertyType.allCases)
        #expect(saved.map(\.id) == fields.map(\.id))
        #expect(saved.map(\.required) == fields.map(\.required))
    }

    @Test func recordLayoutPersistsAndFilteredNavigationIncludesTheOpenRecord() throws {
        var collection = CollectionTemplate.invoices.make(name: "Bills")
        collection.entries = ["Unpaid", "Paid", "Unpaid"].map { .init(values: ["status": $0]) }
        let view = collection.views[1]
        let current = collection.entries[1]
        #expect(view.records(in: collection).count == 2)
        #expect(view.records(in: collection, including: current.id).map(\.id) == collection.entries.map(\.id))
        var layout = RecordTemplate(collection: collection)
        layout.move(field: "client", to: layout.groups.last?.id)
        layout.tabs.append("Notes")
        collection.recordTemplate = layout
        let reopened = try JSONDecoder().decode(PageCollection.self, from: JSONEncoder().encode(collection))
        #expect(reopened.recordTemplate == layout)
        #expect(layout.groups.last?.fields.contains("client") == true)
        #expect(!layout.groups[0].fields.contains("client"))
        #expect(layout.buttons.map(\.title) == ["Mark paid", "Copy invoice number"])
        #expect(RecordTemplate(collection: CollectionTemplate.blank.make(name: "Notes")).buttons.isEmpty)
    }

    @Test func savedViewSurvivesReloadWithFilteredCalculations() throws {
        let domain = "collections-test-" + UUID().uuidString
        let settings = try #require(UserDefaults(suiteName: domain))
        defer { settings.removePersistentDomain(forName: domain) }
        let library = CollectionLibrary(settings: settings)
        var item = CollectionTemplate.invoices.make(name: "Invoices")
        item.entries = (1...12).map { n in
            CollectionEntry(values: ["name": "Invoice \(n)", "amount": "0.10", "status": n == 1 ? "Paid" : "Unpaid"])
        }
        item.selectedView = item.views[1].id
        item.views[1].pageSize = 10
        item.views[1].calculations["amount"] = .sum
        library.collections = [item]

        let loaded = try #require(CollectionLibrary(settings: settings).collections.first)
        let view = try #require(loaded.views.first { $0.id == loaded.selectedView })
        let entries = loaded.entries.filter(view.matches)
        #expect(entries.count == 11)
        #expect(entries.count > view.pageSize)
        #expect(view.calculations["amount"]?.result(entries.compactMap { $0.values["amount"] }) == Decimal(string: "1.1")?.formatted())
        #expect(loaded.properties.first?.required == true)
        #expect(loaded.entries.map(\.id) == item.entries.map(\.id))
    }
}
