import AppKit
import WebKit

extension Browser {
    var canOpenPrivateSpace: Bool { windowPurpose == .normal }

    /// A regular space to inherit when opening another window.
    var spaceForNewWindow: Space {
        guard inPrivateSpace else { return space }
        return spaces.first { $0.id == privateReturnSpace } ?? spaces.first { $0.id == homeSpaceID } ?? spaces[0]
    }

    func openPrivateSpace() {
        if NSApp.currentEvent?.type == .keyDown, NSApp.currentEvent?.isARepeat == true { return }
        guard canOpenPrivateSpace else { return }
        if inPrivateSpace, workspaceSpace == nil {
            if active == nil { askNew() }
        } else {
            switchSpace(to: Space.privateID)
        }
    }

    func leavePrivateSpace() {
        guard inPrivateSpace else { return }
        let destination = privateReturnSpace == Space.mailID && prefs.usesMail ? Space.mailID : spaceForNewWindow.id
        switchSpace(to: destination)
    }

    func privateBrowsingStore() -> WKWebsiteDataStore {
        if let privateStore { return privateStore }
        let store = WKWebsiteDataStore.nonPersistent()
        ChromiumPrivateProfiles.retainSession(store)
        privateStore = store
        return store
    }

    func releasePrivateStore() {
        guard let privateStore else { return }
        ChromiumPrivateProfiles.releaseSession(privateStore)
        self.privateStore = nil
    }

    func endPrivateSession() {
        leavePrivateSpace()
        if let row = parked.removeValue(forKey: Space.privateID) { closePrivateTabs(row.tabs) }
        releasePrivateStore()
    }

    func clearPrivateSession() {
        guard inPrivateSpace else { return }
        SpaceTray.shown?.leave()
        settleNow()
        land()
        hidePeek()
        dismiss()
        let closing = tabs
        quietly {
            pairs = []
            _ = unpick()
            showRow([], active: nil)
            settleUnder()
            closePrivateTabs(closing)
            releasePrivateStore()
            _ = privateBrowsingStore()
            restage()
            query.returnPlace = nil
            askNew()
        }
    }

    private func closePrivateTabs(_ tabs: [Tab]) {
        for tab in tabs {
            dropPeek(of: tab)
            dropAsks(tab)
            pageTranslation.forget(tab)
            tab.close()
        }
    }
}
