import Foundation

struct RecordGroup: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var fields: [String] = []
}

struct RecordButtonProperty: Codable, Identifiable, Equatable {
    enum Command: String, Codable, CaseIterable {
        case copy = "Copy value", set = "Set value"
    }
    var id = UUID()
    var title: String
    var command: Command
    var field: String
    var value = ""
}

struct RecordTemplate: Codable, Equatable {
    var order: [String]
    var groups: [RecordGroup]
    var buttons: [RecordButtonProperty]
    var tabs: [String]

    init(collection: PageCollection) {
        order = collection.properties.dropFirst().map(\.id)
        groups = []
        buttons = []
        tabs = ["Overview"]
        let fields = collection.properties.dropFirst().map(\.id)
        let legacyInvoice = collection.views.contains { view in
            view.name == "Outstanding" && view.filters.contains { $0.property == "status" && $0.value == "Unpaid" }
        } || (collection.symbol == CollectionTemplate.invoices.symbol && Set(["client", "status", "amount"]).isSubset(of: Set(fields)))
        if collection.sourceTemplate.map({ $0 == .invoices }) ?? legacyInvoice {
            let payment = fields.filter { ["status", "amount"].contains($0) }
            groups = [RecordGroup(title: "Invoice details", fields: fields.filter { !payment.contains($0) }),
                      RecordGroup(title: "Payment", fields: payment)].filter { !$0.fields.isEmpty }
            if fields.contains("status") {
                buttons.append(.init(title: "Mark paid", command: .set, field: "status", value: "Paid"))
            }
            buttons.append(.init(title: "Copy invoice number", command: .copy, field: "name"))
        }
    }

    mutating func move(field: String, to group: UUID?) {
        for i in groups.indices { groups[i].fields.removeAll { $0 == field } }
        if let i = groups.firstIndex(where: { $0.id == group }) { groups[i].fields.append(field) }
    }
}

struct OpenRecord: Identifiable {
    var id: UUID { record }
    let collection: UUID
    var record: UUID
    let view: UUID
    let page: Int
}

extension Browser {
    func showCollection(_ id: UUID) {
        collectionID = id
        currentRecord = nil
        customizingRecord = false
        creatingCollection = false
    }

    func showRecord(_ tab: OpenRecord, replacing: Bool = false) {
        if let existing = recordTabs.firstIndex(where: { $0.id == tab.id }) {
            recordTabs[existing] = tab
            if replacing, currentRecord != tab.id { recordTabs.removeAll { $0.id == currentRecord } }
        } else if replacing, let current = recordTabs.firstIndex(where: { $0.id == currentRecord }) {
            recordTabs[current] = tab
        } else {
            recordTabs.append(tab)
        }
        collectionID = tab.collection
        currentRecord = tab.id
        customizingRecord = false
        creatingCollection = false
    }

    @discardableResult func closeCurrentRecord() -> Bool {
        guard inCollections, !creatingCollection, let tab = recordTabs.first(where: { $0.id == currentRecord }) else { return false }
        closeRecord(tab)
        return true
    }

    func closeRecord(_ tab: OpenRecord) {
        recordTabs.removeAll { $0.id == tab.id }
        guard currentRecord == tab.id else { return }
        showCollection(tab.collection)
        if let i = CollectionLibrary.shared.collections.firstIndex(where: { $0.id == tab.collection }) {
            CollectionLibrary.shared.collections[i].selectedView = tab.view
        }
        collectionPages[tab.view] = tab.page
    }
}
