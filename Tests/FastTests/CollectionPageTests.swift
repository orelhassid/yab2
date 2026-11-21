import Foundation
import Testing
@testable import Fast

@Suite @MainActor
struct CollectionPageTests {
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
