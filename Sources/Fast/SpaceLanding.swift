import Foundation

/// A place in the space on screen, counted without the carried tabs.
enum SpaceLanding: Equatable {
    case todayTop
    case row(index: Int, kept: Bool, nest: UUID?)
    case pin(Int)
    case folder(UUID)
}

extension Browser {
    /// Commit a spring-loaded drag only at let-go. Visiting spaces never
    /// moves a page (nor changes its sign-ins). The transfer and its final
    /// arrangement share one undo step, including the space we left.
    @discardableResult
    func landTabs(_ picked: [Tab], from home: UUID, to target: UUID, at landing: SpaceLanding,
                  folder: Nest? = nil, showing: Bool = true) -> [Tab] {
        guard prefs.usesSpaces, home != target, spaces.contains(where: { $0.id == home }),
              spaces.contains(where: { $0.id == target }) else { return [] }
        // These synchronous switches are bookkeeping within this commit.
        // Only the final row is presented; the pager has already brought it.
        let still = SpaceTurn.still
        SpaceTurn.still = true
        SpacePager.shared.finish()
        defer { SpaceTurn.still = still }
        arrangeDepth += 1
        defer { arrangeDepth -= 1 }
        if spaceID != home { switchSpace(to: home) }
        let before = RowShape(self), chosen = activeID
        // The tab in front over there, given back by undo: undoMove clears
        // it, and the next visit opened the field over an empty page.
        let targetChosen = parked[target]?.active
        let empty = folder.map { nest in folderBook.empties.filter { $0.within(nest) } } ?? []
        let parent = folder?.parent
        let fleeting = folder?.fleeting
        let search = folder?.search
        let move: SpaceMove?
        if let folder {
            move = sendFolder(folder, to: target)
        } else {
            move = moveTabs(picked, to: target, say: false, step: false, top: true)
        }
        guard move != nil || !empty.isEmpty else {
            if showing { switchSpace(to: target) }
            return []
        }
        switchSpace(to: target)
        let arrived = move?.tabs.map(\.now) ?? []
        placeCarried(arrived, at: landing, folder: folder)
        did { [weak self] in
            guard let self else { return }
            // Unpin new shared squares before switching home: simply
            // clearing everywhere is undone by switchSpace's settleShared.
            let shared = (move?.tabs ?? []).filter { moved in
                moved.now.everywhere != nil && before.marks.first(where: { $0.tab.id == moved.original })?.everywhere == nil
            }
            if !shared.isEmpty {
                if spaceID != target { switchSpace(to: target) }
                for moved in shared where moved.now.pin != nil { unpin(moved.now) }
            }
            if spaceID != home { switchSpace(to: home) }
            if let move {
                undoMove(move)
                if var row = parked[target], row.active == nil, let targetChosen,
                   row.tabs.contains(where: { $0.id == targetChosen }) {
                    row.active = targetChosen
                    parked[target] = row
                    writeRow(row.tabs, active: row.active, space: target, pairs: row.pairs, now: true)
                }
            } else {
                folder?.parent = parent
                folderBook.send(empty, from: target, to: home)
            }
            if let folder, let fleeting { folder.fleeting = fleeting; folder.search = search }
            // Different sign-ins reopen the pages on the way back too.
            // Restore the source marks/order against those new identities.
            var replacements: [Tab.ID: Tab] = [:]
            for moved in move?.tabs ?? [] where !tabs.contains(where: { $0.id == moved.original }) {
                if tabs.indices.contains(moved.at) { replacements[moved.original] = tabs[moved.at] }
            }
            put(before, replacing: replacements)
            if let chosen, let tab = replacements[chosen] ?? tabs.first(where: { $0.id == chosen }) { select(tab) }
        }
        if !showing { switchSpace(to: home) }
        return arrived
    }

    /// The same landing in the home space after a swipe out and back.
    func placeCarried(_ arrived: [Tab], at landing: SpaceLanding, folder: Nest? = nil) {
        let ids = Set(arrived.map(\.id))
        if case .pin(let at) = landing {
            if let first = arrived.first, let pair = pair(of: first.id),
               Set([pair.first, pair.second]) == ids, canPinPair(pair) {
                pinPair(pair, cell: at)
            } else {
                pin(arrived, at: at)
            }
            folderBook.refresh()
            if let first = arrived.first { select(first) }
            rememberSession()
            return
        }
        let rest = tabs.filter { $0.pin == nil && !ids.contains($0.id) }
        let keptCount = rest.prefix(while: \.kept).count
        let nest: Nest?
        let kept: Bool
        let index: Int
        switch landing {
        case .todayTop:
            kept = folder.map { !$0.today } ?? false
            nest = nil
            index = keptCount
        case .row(let at, let keep, let id):
            kept = keep
            nest = id.flatMap { id in nests.first { $0.id == id } }
            index = at
        case .folder(let id):
            nest = nests.first { $0.id == id }
            kept = nest?.today != true
            if let nest {
                let end = rest.lastIndex { $0.nest?.within(nest) == true }.map { $0 + 1 }
                index = end ?? (kept ? folderBook.standIndex(for: nest, in: rest.filter(\.kept)) ?? keptCount : rest.count)
            } else { index = keptCount }
        case .pin: return
        }
        if let folder {
            let tree = nests.filter { $0.within(folder) }
            if kept {
                for each in tree { each.ordinaryToday = false; each.fleeting = false; each.search = nil }
            } else if !folder.today {
                for each in tree { each.ordinaryToday = true }
            }
            folder.parent = canPut(folder, in: nest) ? nest : nil
            for each in folderBook.empties where each.within(folder) { folderBook.emptyChanged(each) }
            if arrived.isEmpty { folder.stand = rest.indices.contains(index) ? Nest.Stand(before: rest[index].id) : nil }
        }
        for tab in arrived {
            if tab.pin != nil { unpin(tab) }
            tab.kept = kept && tab.keepable
            if folder == nil { tab.nest = nest }
        }
        let pins = tabs.filter { $0.pin != nil && !ids.contains($0.id) }
        var loose = tabs.filter { $0.pin == nil && !ids.contains($0.id) }
        let at = kept ? min(max(0, index), keptCount) : min(max(keptCount, index), loose.count)
        loose.insert(contentsOf: arrived, at: at)
        lay(pins + loose)
        folderBook.refresh()
        if let first = arrived.first { select(first) }
        rememberSession()
    }

}
