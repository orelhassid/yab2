import AppKit
import CoreSpotlight
import SyncKit

// Links from elsewhere. A click in Mail, in Slack, in a PDF, macOS hands the
// address to whichever app owns http, and this is how that app takes it.
//
// The bundle says it owns http and https (build.sh writes that into the
// plist); this is the other half. Addresses can arrive before the window has
// been built, so they wait here until the browser says it is ready for them.

final class Links: NSObject, NSApplicationDelegate {
    private let continueWebPage: (URL, String?) -> Void

    override init() {
        continueWebPage = Links.continuePage
        super.init()
    }

    /// The same delegate path with an isolated destination for unit tests.
    init(continueWebPage: @escaping (URL, String?) -> Void) {
        self.continueWebPage = continueWebPage
        super.init()
    }

    private var iconAppearanceObservation: NSObjectProtocol?
    /// Where an address goes once there is somewhere for it to go.
    private static var deliver: ((URL, UUID?) -> Void)?
    /// Addresses that arrived first.
    private static var waiting: [(url: URL, recent: UUID?)] = []
    private static var waitingNewTabs = 0
    /// The browser's window, once there is one.
    private static weak var firstWindow: NSWindow?
    static var window: NSWindow? {
        get { MainActor.assumeIsolated { BrowserWindows.shared.activeWindow ?? firstWindow } }
        set { firstWindow = newValue }
    }
    /// The browser, which is made before its window: a link that launches
    /// the app can go to a small window with no browser window at all.
    private static weak var firstBrowser: Browser?
    static var browser: Browser? {
        get { MainActor.assumeIsolated { BrowserWindows.shared.activeBrowser ?? firstBrowser } }
        set { firstBrowser = newValue }
    }
    /// Whether the window has been asked for on a link's behalf (summon).
    private static var summoned = false
    /// Set by a quit that was already agreed to, Restart after an update,
    /// so it isn't asked about a second time.
    static var leaving = false

    /// With "Warn before quitting" on, ⌘Q asks first, in the card yab asks
    /// everything in (Question.swift): Return quits, Escape stays, and a
    /// second ⌘Q while it is up quits as well, so the hand that pressed it
    /// twice isn't slowed. Only a quit a person set off: logging out or
    /// shutting down arrives as an Apple event and goes without a word, and
    /// with the window closed there is nothing to ask it in.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // A page holding something typed asks first (LeavePage.swift), and its Leave is the quit's yes. Most pages
        // answer in this call; one that asks or is slow to answer quits
        // again once it has.
        var pagesAsked = false
        if !Links.leaving, NSAppleEventManager.shared().currentAppleEvent == nil {
            let held: NSApplication.TerminateReply? = MainActor.assumeIsolated {
                if let agreed = Links.pagesAgreed {
                    Links.pagesAgreed = nil
                    pagesAsked = agreed
                    return nil
                }
                if Links.askingPages { return .terminateCancel }
                var now: (leave: Bool, asked: Bool)?
                var waiting = true
                Leaving.quit { leave, asked in
                    guard !waiting else { now = (leave, asked); return }
                    Links.askingPages = false
                    guard leave else { return }
                    Links.pagesAgreed = asked
                    RunLoop.main.perform { MainActor.assumeIsolated { NSApp.terminate(nil) } }
                }
                waiting = false
                guard let now else {
                    Links.askingPages = true
                    return .terminateCancel
                }
                guard now.leave else { return .terminateCancel }
                pagesAsked = now.asked
                return nil
            }
            if let held { return held }
        }
        // On a call it asks whatever the setting says: quitting hangs up.
        // With agents at work too: it can let them finish (Headless.linger).
        let calling = MainActor.assumeIsolated { BrowserWindows.shared.browsers.contains { $0.calls.any } }
        let working = MainActor.assumeIsolated { !Links.agentsAtWork.isEmpty }
        let warn = !pagesAsked && Store.settings.object(forKey: "quit.warn") as? Bool ?? true
        guard calling || working || warn, !Links.leaving,
              NSAppleEventManager.shared().currentAppleEvent == nil,
              Links.window?.isVisible == true
        else {
            return MainActor.assumeIsolated { quit() }
        }
        return MainActor.assumeIsolated {
            if Links.askingToQuit {
                // The second ⌘Q is the yes: with agents at work, quit when
                // they are done, as Return would.
                if let asked = Links.quitAsked, Questions.shared.current?.id == asked {
                    Questions.shared.answer(true)
                    return .terminateCancel
                }
                return quit()
            }
            Links.askingToQuit = true
            let question = Links.quitQuestion()
            // Only what goes on without you is waited for: a task waiting
            // on you stops with the quit.
            let lets = !Links.agentsGoingOn.isEmpty && !calling
            Links.quitAsked = question.id
            Task { @MainActor in
                let quit = await Questions.shared.ask(question)
                Links.askingToQuit = false
                Links.quitAsked = nil
                guard quit else { return }
                // Agents at work and Quit When Done: the windows go, and
                // yab quits once the last task ends.
                if lets, !Questions.shared.ticked, !Links.agentsGoingOn.isEmpty {
                    Headless.linger()
                    return
                }
                // Only with Quit: Cancel with the box ticked changes nothing.
                if !lets, Questions.shared.ticked { Links.stopAsking?() }
                Links.leaving = true
                BrowserWindows.shared.prepareToQuit()
                // From the run loop, not this block on the main queue: a
                // call's page is seen off while yab waits to quit, and its
                // steps are blocks on the queue this one would hold.
                RunLoop.main.perform { MainActor.assumeIsolated { NSApp.terminate(nil) } }
            }
            return .terminateCancel
        }
    }

    /// Quitting now, the session written first, and the cookies that live
    /// only as long as the browser kept for the next launch (KeptCookies),
    /// two seconds at most. A call's page leaves its call before yab goes
    /// (Farewell, Tab.swift): its own Leave, then its goodbye, so the
    /// meeting hears you leave rather than lose you, four seconds at most.
    /// Ended with the process, it kept you in the call for everyone else
    /// until it gave up on you.
    @MainActor private func quit() -> NSApplication.TerminateReply {
        if EngineSwitchQuit.deferQuitIfNeeded() { return .terminateCancel }
        BrowserWindows.shared.prepareToQuit()
        let calls = BrowserWindows.shared.browsers.flatMap { $0.everyTab.filter(\.onCall) }
        calls.forEach { $0.close() }
        var waiting = 2
        func ready() {
            waiting -= 1
            if waiting == 0 { NSApp.reply(toApplicationShouldTerminate: true) }
        }
        KeptCookies.save { ready() }
        if calls.isEmpty { ready() } else { Farewell.whenDone(within: 4) { ready() } }
        return .terminateLater
    }

    /// "Don't ask again", ticked: Settings' "Warn before quitting" off,
    /// through the browser's settings so its switch shows it.
    private static var stopAsking: (@MainActor () -> Void)?

    /// While pages are asked whether they may go: another ⌘Q waits on them.
    @MainActor private static var askingPages = false
    /// Set as the pages' yes quits again: whether one of them asked, which
    /// stands for ⌘Q's own question.
    @MainActor private static var pagesAgreed: Bool?

    /// While ⌘Q's question is up: another ⌘Q is the yes.
    @MainActor private static var askingToQuit = false
    @MainActor private static var quitAsked: UUID?

    /// Agents' tasks still running, the ones a quit would stop.
    @MainActor static var agentsAtWork: [Agents.Session] {
        Agents.shared.sessions.filter(\.atWork)
    }

    /// The ones of those that go on without you, which Quit When Done
    /// waits for.
    @MainActor static var agentsGoingOn: [Agents.Session] {
        Agents.shared.sessions.filter(\.goingOn)
    }

    /// What quitting takes away, said under the question: nothing is lost,
    /// the tabs come back. An agent at work can finish first: the windows
    /// go now and yab when it's done, or Stop and Quit stops it now. It
    /// asks by the app's own name and wears its own icon, the way the Dock
    /// names and shows it: yab, yab Dev and Open yab each ask as themselves.
    @MainActor private static func quitQuestion() -> Question {
        let working = agentsGoingOn
        let waiting = agentsAtWork.filter { !$0.goingOn }
        let calling = BrowserWindows.shared.browsers.contains { $0.calls.any }
        if calling {
            return Question(title: "Quit \(appName)?", detail: "You’re on a call. Quitting ends it.", icon: NSApp.applicationIconImage,
                            ownIcon: true, yes: "Quit")
        }
        func who(_ sessions: [Agents.Session]) -> String {
            sessions.count == 1 ? "\(sessions[0].name) is" : "\(sessions.count) agents are"
        }
        switch working.count {
        case 0 where !waiting.isEmpty:
            // Nobody would answer it with the windows gone: it stops.
            return Question(title: "Quit \(appName)?", detail: "\(who(waiting)) waiting on you. Quitting stops \(waiting.count == 1 ? "it" : "them").",
                            icon: NSApp.applicationIconImage, ownIcon: true, yes: "Quit")
        case 0:
            return Question(title: "Quit \(appName)?", detail: "Your tabs will be here when you come back.", icon: NSApp.applicationIconImage,
                            ownIcon: true, yes: "Quit", box: "Don’t ask again")
        default:
            return Question(title: "Quit \(appName)?", detail: "\(who(working)) still working. The windows close now, and \(appName) quits when \(working.count == 1 ? "it’s" : "they’re") done.",
                            icon: NSApp.applicationIconImage, ownIcon: true, yes: "Quit When Done",
                            other: "Stop and Quit")
        }
    }

    /// The name the bundle gives the app, what the Dock and the menu bar
    /// call it; a bare SwiftPM run has no bundle and is yab.
    static var appName: String {
        (Bundle.main.infoDictionary?["CFBundleName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Yab"
    }

    func applicationWillTerminate(_ notification: Notification) {
        LaunchJournal.record("browser.terminate")
        MainActor.assumeIsolated {
            BrowserWindows.shared.prepareToQuit()
            // The icons pages wore in the last seconds, for their tabs
            // coming back (Favicons.pageIcon).
            Favicons.shared.savePagesNow()
            CrashSessions.finish()
        }
    }

    /// A run straight from the SwiftPM binary has no Info.plist, and macOS
    /// takes an app without one for a background process: no Dock tile, no
    /// menu bar, and a window that opens behind whatever was in front. So
    /// it says what it is, wears the mark in the Dock, and comes forward,
    /// the way the built app does on its own.
    static func standUp() {
        guard Bundle.main.bundleIdentifier == nil else { return }
        NSApp.setActivationPolicy(.regular)
        NSApp.applicationIconImage = dockIcon()
        DispatchQueue.main.async { NSApp.activate(ignoringOtherApps: true) }
    }

    /// A masked fallback for a bare SwiftPM run, using the development
    /// bundle's current source artwork.
    static func dockIcon() -> NSImage {
        NSImage(size: NSSize(width: 512, height: 512), flipped: false) { rect in
            let tile = rect.insetBy(dx: 50, dy: 50)
            let shape = NSBezierPath(roundedRect: tile, xRadius: 92, yRadius: 92)
            NSColor(srgbRed: 0, green: 0.114, blue: 0.227, alpha: 1).setFill()
            shape.fill()
            // Its own 1024 points, drawn to the edge of the tile.
            shape.addClip()
            if let blueprint = Logomark.file("yab Dev.icon/Assets/blueprint.png").flatMap({ NSImage(contentsOf: $0) }) {
                blueprint.draw(in: tile, from: .zero, operation: .sourceOver, fraction: 1)
            }
            return true
        }
    }

    /// Every reported or uncaught exception written down before a later crash:
    /// its time, name, reason and stack, appended, so it survives the
    /// crash. When crash reports are sent (Crashes), the one just before a
    /// crash goes with its report, cleaned; nothing else here leaves the Mac.
    /// Crashes.thrown reads it back: keep the time first and the empty line
    /// after.
    @MainActor static func watchForTrouble() {
        AppKitExceptionLog.install(file: Store.file("crash.log"))
    }

    /// Addresses come in as Apple Events, one each. Taking them straight
    /// from the event manager keeps them out of SwiftUI's hands: left to it,
    /// every address handed at launch had the window presented afresh, and
    /// five of them meant five rebuilds of the content before the window
    /// had shown once.
    func applicationWillFinishLaunching(_ notification: Notification) {
        Browser.clearLeftoverDownloads()
        MainActor.assumeIsolated { Startup.mark("will launch") }
        defer { MainActor.assumeIsolated { Startup.mark("will launch done") } }
        MainActor.assumeIsolated {
            ChromiumAccessibilityClient.install()
            ChromiumProcess.startAhead()
        }
        // Boosts' safe mode is ⌥ held as Yab opens, read now.
        MainActor.assumeIsolated { Boosts.optionAtLaunch = NSEvent.modifierFlags.contains(.option) }
        // Yab's page scripts and the presses around them, for evals/activation.
        WebKitIPCBoundary.install()
        EvalTrace.install()
        // The Mac's own window tabs: yab's tabs are its own, so macOS adds
        // no New Tab and no Show Tab Bar to the Window and View menus.
        NSWindow.allowsAutomaticWindowTabbing = false
        // A page's own full screen from a window in full screen grows in
        // place, not after a slide over a black desktop (PageFullScreenMove).
        MainActor.assumeIsolated { PageFullScreenMove.watch() }
        if Headless.on { MainActor.assumeIsolated { Headless.launch() } } else { Links.standUp() }
        MainActor.assumeIsolated { AppIconStyle.applySaved() }
        // The Mac turning light or dark, not the Theme: the Dock follows the
        // Mac. A beat after, so the setting has turned over (Browser.relook).
        iconAppearanceObservation = DistributedNotificationCenter.default().addObserver(
            forName: AppIconStyle.systemChanged, object: nil, queue: .main
        ) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { AppIconStyle.applySaved() }
        }
        // Sign-ins the last hidden run kept on its way out (KeptCookies).
        MainActor.assumeIsolated { KeptCookies.restore() }
        // Before launching ends, as macOS asks: a click on a notification
        // that started Yab reaches it.
        MainActor.assumeIsolated { AgentNotices.listen() }
        Links.watchForTrouble()
        // Logging out, restarting or shutting down, Software Update's restart
        // too: that one asks Yab to quit with no Apple event, so without this
        // it took the quit for a ⌘Q, asked, and its Cancel stopped the restart
        // halfway with the other apps already gone.
        _ = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main
        ) { _ in Links.leaving = true }
        Vault.adopt()
        Vault.refresh()
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handle(getURL:reply:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL)
        )
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handle(openDocuments:reply:)),
            forEventClass: AEEventClass(kCoreEventClass), andEventID: AEEventID(kAEOpenDocuments)
        )
    }

    /// A launch macOS doesn't call a plain one, started hidden as `open -j`
    /// or anything asking for a hidden launch does, SwiftUI can treat like
    /// the launch a link makes: it leaves its window to whatever the launch
    /// came for, and the app ran with no window at all. The window is asked
    /// for here instead; started hidden, it stays hidden with the app until
    /// the app is shown.
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            Startup.mark("launched")
            Watchdog.start()
            // Fields of many lines scroll their words under a wheel and
            // two fingers (FieldWheel, #129).
            FieldWheel.start()
            // No menu wider than its everyday words (MenuWidth).
            MenuWidth.start()
            // Send Feedback's key in Settings and Yab's other windows.
            FeedbackSheet.listen()
            // A debug build: every stop of 50 ms, into its journal.
            if DebugLog.freezes {
                Hangs.start()
                DebugLog.note("launched", ["debug": DebugLog.channels.sorted(),
                                           "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""])
                DebugLog.screens()
            }
            // Live folders read on their own clock (LiveFolders.swift),
            // started once the launch is over.
            Startup.later("live folders") { LiveFolders.shared.start() }
            // Assistants in the cloud find this Mac after launch too.
            Startup.later("assistant host") { AssistantHost.shared.start() }
            // The chats kept from before, read off the main thread.
            Chats.shared.load()
        }
        let plain = notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool ?? true
        // Opened by macOS at login with Open at Login on: hidden as a woken
        // Yab is, with sync (OpenAtLogin). Asked now, while the launch's
        // own Apple event is the current one.
        let atLogin = MainActor.assumeIsolated { OpenAtLogin.began() }
        // Sync, once the windows have their rows back (SyncCenter); not for
        // a Yab woken only for agents until someone shows it or it serves
        // (Headless), nor a test world unless it names a server of its own.
        // Once the launch is over (Startup.later): it catches up then.
        if !Headless.on || MainActor.assumeIsolated({ Headless.serving }), SyncCenter.mayRun {
            MainActor.assumeIsolated { Startup.later("sync") { SyncCenter.shared.launchIfNeeded() } }
        }
        // Sites' pushes with their tabs closed: the socket to the push
        // service, if any site has a subscription (WebPush.swift).
        MainActor.assumeIsolated { Startup.later("web push") { WebPush.shared.launch() } }
        // Woken for agents, or opened at login: no window until someone
        // asks for one.
        if Headless.on || atLogin {
            MainActor.assumeIsolated { Headless.settle(plain: plain) }
            return
        }
        // A launch a link made has its own way to a window (take), its
        // small one included, which a browser window here would cover.
        guard !plain, !Links.arrived else { return }
        // Once, and only with no window made yet (see summon).
        DispatchQueue.main.async { Links.summon() }
    }

    func application(
        _ application: NSApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void
    ) -> Bool {
        // A page picked up from the iPhone (or another Mac) by Handoff.
        if userActivity.activityType == ContinuePage.type || userActivity.activityType == ContinuePage.webType,
           let arrival = ContinuePage.arrival(webpageURL: userActivity.webpageURL, userInfo: userActivity.userInfo) {
            continueWebPage(arrival.url, arrival.space)
            return true
        }
        guard userActivity.activityType == CSSearchableItemActionType,
              let identifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
              identifier.hasPrefix("bookmark:"),
              let id = UUID(uuidString: String(identifier.dropFirst("bookmark:".count))),
              let url = MainActor.assumeIsolated({ Bookmarks.shared.url(for: id) }),
              Bookmark.keepable(url)
        else { return false }
        Links.take(url)
        return true
    }

    @objc private func handle(getURL event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let text = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: text) else { return }
        // A Store link: the pinned revision on trial in a tab of its own.
        if url.scheme == "yab-boost", let revision = url.host, BoostShare.validRevision(revision) {
            MainActor.assumeIsolated {
                guard let browser = BrowserWindows.shared.browsers.first else { return }
                Task {
                    do { try await BoostShare.fetch(revision, in: browser) }
                    catch { browser.announce(error.localizedDescription, mark: "exclamationmark.triangle") }
                }
            }
            return
        }
        // A mail link from another app, Yab the Mac's mail app (MailtoPeek.swift).
        if url.scheme?.lowercased() == "mailto" {
            Links.takeMail(url)
            return
        }
        guard url.scheme?.lowercased().hasPrefix("http") == true else { return }
        Links.take(url)
    }

    /// Files the system opens with the app: a page on this Mac, an .html or
    /// .xhtml double-clicked in the Finder once yab is the Mac's browser,
    /// or a .webloc. Taken from the event manager as addresses are: left to
    /// SwiftUI, one that launched the app never reached the delegate, and
    /// the page was dropped unseen.
    @objc private func handle(openDocuments event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let list = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject)) else { return }
        let items = list.numberOfItems > 0 ? (1...list.numberOfItems).compactMap { list.atIndex($0) } : [list]
        for item in items {
            guard let file = item.fileURLValue, let url = Links.inside(file),
                  url.isFileURL || url.scheme?.lowercased().hasPrefix("http") == true
            else { continue }
            Links.take(url)
        }
    }

    /// A .webloc is the address it keeps, not a page of its own.
    private static func inside(_ url: URL) -> URL? {
        guard url.isFileURL, url.pathExtension.lowercased() == "webloc" else { return url }
        guard let data = try? Data(contentsOf: url),
              let list = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let text = list["URL"] as? String, let address = URL(string: text)
        else { return nil }
        return address
    }

    /// The Dock icon clicked with the window closed: bring the window back
    /// rather than doing nothing, which is what a hidden-title-bar SwiftUI
    /// window does by default.
    ///
    /// A small window up for a link counts as a visible window to macOS, and
    /// may be the only window there is: the Dock brings the browser then too.
    /// Never for the last window: closed, yab stays for the Dock to bring
    /// it back, and hidden for agents it has no window at all.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if MainActor.assumeIsolated({ Headless.hidden }) {
            MainActor.assumeIsolated {
                Headless.show(.person)
                Links.showBrowser()
                NSApp.activate()
            }
            return false
        }
        if Links.window?.isVisible != true, !LinkWindow.all.isEmpty {
            MainActor.assumeIsolated { Links.showBrowser() }
            return false
        }
        // Whether a window is up is asked here rather than taken from
        // macOS: its flag counts the room too, the window on no screen that
        // agents' pages are laid out in (Bench.house), so once an agent had
        // worked in a page it said yes with nothing on screen, and the
        // click brought nothing back. A floating video joins every Space, so
        // it is up here whichever one is in front and says nothing about
        // the window: left to macOS, with Yab in full screen on a Space of
        // its own, the click ended on a bare desktop with the video on it.
        // That window counts only on the Space in front.
        MainActor.assumeIsolated {
            let windows = NSApp.windows.filter { $0.identifier != Bench.roomID && !$0.collectionBehavior.contains(.canJoinAllSpaces) }
            guard !windows.contains(where: { $0.isVisible && $0.isOnActiveSpace }) else { return }
            (Links.window ?? windows.first { $0.contentView != nil && LinkWindow.owning($0) == nil })?.makeKeyAndOrderFront(nil)
        }
        return true
    }

    /// The Dock icon's menu, as every browser has one: the windows, which
    /// macOS lists by their titles (BrowserWindows.retitle), then these,
    /// then its own Options, Show All Windows, Hide and Quit. With more
    /// than one space, a new window in each, as Dia offers one a profile.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: "New Window", action: #selector(dockNewWindow), keyEquivalent: "").target = self
        let spaces = MainActor.assumeIsolated { () -> [Space] in
            guard let browser = Links.browser, browser.prefs.usesSpaces, browser.spaces.count > 1 else { return [] }
            return browser.spaces
        }
        for space in spaces {
            let title = "New Window in \(space.marked())"
            let short = MainActor.assumeIsolated { MenuWidth.cut(title, font: .menuFont(ofSize: 0)) }
            let item = menu.addItem(withTitle: short ?? title, action: #selector(dockNewWindowInSpace), keyEquivalent: "")
            if short != nil { item.toolTip = title } // design: NSMenuItem has no view to wear a keyTip
            item.target = self
            item.representedObject = space.id
        }
        menu.addItem(withTitle: "New Private Window", action: #selector(dockPrivateTab), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Change App Icon…", action: #selector(dockChangeAppIcon), keyEquivalent: "").target = self
        return menu
    }

    @objc private func dockNewWindowInSpace(_ item: NSMenuItem) {
        guard let space = item.representedObject as? UUID else { return }
        MainActor.assumeIsolated {
            Headless.show(.person)
            BrowserWindows.shared.newWindow(from: Links.browser, space: space)
        }
    }

    @objc private func dockNewWindow() {
        MainActor.assumeIsolated {
            Headless.show(.person)
            BrowserWindows.shared.newWindow(from: BrowserWindows.shared.activeBrowser ?? Links.browser)
        }
    }

    /// In the window in front, as ⇧⌘N does it; brought back if it was closed.
    @objc private func dockPrivateTab() {
        MainActor.assumeIsolated {
            Headless.show(.person)
            guard let target = BrowserWindows.shared.activeBrowser ?? Links.browser else { return }
            target.newPrivateWindow()
            NSApp.activate()
        }
    }

    @objc private func dockChangeAppIcon() {
        MainActor.assumeIsolated {
            Headless.show(.person)
            guard let target = BrowserWindows.shared.activeBrowser ?? Links.browser else { return }
            SettingsWindow.shared.show(.appIcon, for: target)
        }
    }

    /// The browser's window, in front: brought back if it was closed, and
    /// made for the first time if a link launched the app into a small
    /// window and nothing else.
    @MainActor
    static func showBrowser(_ browser: Browser? = nil) {
        if let target = browser.flatMap({ BrowserWindows.shared.window(for: $0) }) ?? window {
            target.makeKeyAndOrderFront(nil)
        } else {
            summoned = true
            _ = NSApp.delegate?.applicationOpenUntitledFile?(NSApp)
        }
    }

    /// Whether a link goes to a small window rather than a tab: asked for,
    /// and past the welcome, which is the browser's window's to give. Never
    /// a meeting: a call wants the whole window and a tab of its own, one
    /// Escape can't close, as Arc learned.
    @MainActor
    private static func small(_ browser: Browser?, for url: URL) -> Browser? {
        guard LinkWindow.wanted, !CallLink.isCall(url), let browser, browser.prefs.welcomed,
              !LinkRoutes.shared.opensInMain(for: url) else { return nil }
        return browser
    }

    /// The browser, once it has a window. Anything that came earlier is
    /// handed over now, but none of it before the window is on screen.
    ///
    /// Five addresses at launch used to mean five web views built before the
    /// first frame, and a window that took a second to appear instead of a
    /// third of one. Now the window comes first; the first page goes into
    /// the blank tab that is already there, and the others fill in behind
    /// it, a few frames apart, in the order they came.
    @MainActor
    static func hand(to browser: Browser) {
        deliver = { [weak browser] url, recent in
            let target = BrowserWindows.shared.activeBrowser ?? browser
            // Its site's space, if a route keeps it one (LinkRoutes.swift).
            let home = target.flatMap { LinkRoutes.shared.externalSpace(for: url, in: $0, recent: recent) }
            if let smallBrowser = small(target, for: url) {
                LinkWindow.show(url, for: smallBrowser, home: home)
                return
            }
            if let home { target?.switchSpace(to: home) }
            // A meeting already open, in any space, is gone back to.
            if target?.openCall(url) != true { target?.arrive(url) }
            // Address the window that received the link even when it is
            // already visible on another desktop. Activating the app alone
            // does not ask that window to come forward (feedback #1177).
            showBrowser(target)
            // In front of the app the link was clicked in. Since macOS 14 an
            // app asked to open something is let in front, and asks with
            // `activate()`: the old call's "ignoring other apps" is ignored,
            // and the window stayed behind.
            NSApp.activate()
        }
        stopAsking = { [weak browser] in browser?.prefs.warnsOnQuit = false }
        let newTabs = waitingNewTabs
        waitingNewTabs = 0
        if newTabs > 0 {
            onceShown { [weak browser] in
                guard let browser else { return }
                // However many were asked for, one field: a tab comes only
                // with a place to put in it.
                browser.newTab()
                showBrowser(browser)
                NSApp.activate()
            }
        }
        let early = waiting
        waiting = []
        guard let first = early.first else { return }
        onceShown { [weak browser] in
            if let browser, let home = LinkRoutes.shared.externalSpace(for: first.url, in: browser, recent: first.recent) { browser.switchSpace(to: home) }
            browser?.arrive(first.url)
            for (n, url) in early.dropFirst().enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15 * Double(n + 1)) { [weak browser] in
                    if let browser { openQueued(url.url, in: browser, recent: url.recent) }
                }
            }
        }
    }

    /// Every external URL received during launch uses the same destination
    /// policy. Fixed rules count even when no fallback space is configured.
    @MainActor
    static func openQueued(_ url: URL, in browser: Browser, recent: UUID?) {
        if let home = LinkRoutes.shared.externalSpace(for: url, in: browser, recent: recent) {
            browser.switchSpace(to: home)
        }
        browser.open(url, foreground: false, atEnd: true)
    }

    /// Runs once a window is actually showing, and one turn of the run loop
    /// after that, so the frame is on the screen before the work starts.
    /// Gives up waiting after a second or so and runs anyway.
    @MainActor
    static func onceShown(_ then: @escaping () -> Void, tries: Int = 0) {
        let shown = NSApp.windows.contains { $0.isVisible && $0.contentView != nil }
        if shown || tries > 40 {
            DispatchQueue.main.async(execute: then)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { onceShown(then, tries: tries + 1) }
        }
    }

    /// A link has come in since launch.
    private static var arrived = false

    static func take(_ url: URL, tries: Int = 0, recentSpace: UUID? = nil) {
        // Codex's sign-in, which it opens in the Mac's own browser, this one
        // when Yab is that: Connect's tab, not a tab like any other.
        if tries == 0, MainActor.assumeIsolated({ Agents.shared.adoptSignIn(url) }) { return }
        let recent = tries == 0 ? (recentSpace ?? MainActor.assumeIsolated {
            (BrowserWindows.shared.activeBrowser ?? browser)?.spaceID
        }) : recentSpace
        arrived = true
        MainActor.assumeIsolated { Headless.show(.person) }
        if let deliver {
            deliver(url, recent)
        } else if let browser = MainActor.assumeIsolated({ small(browser, for: url) }) {
            // Launched by the link: its small window, and no other.
            MainActor.assumeIsolated { LinkWindow.show(url, for: browser, home: LinkRoutes.shared.externalSpace(for: url, in: browser, recent: recent)) }
        } else if browser == nil, LinkWindow.wanted, !CallLink.isCall(url), tries < 25 {
            // The browser is made as SwiftUI builds the app, which can be a
            // moment after the link that launched it: wait for it rather
            // than give the link a window it didn't need.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { take(url, tries: tries + 1, recentSpace: recent) }
        } else {
            waiting.append((url: url, recent: recent))
            DispatchQueue.main.async { summon() }
        }
    }

    /// A page picked up from another device by Handoff (PageContinuity): a
    /// tab in the window, in the space it was in there when this Mac has that
    /// one, never the small link window, which is for a link from another
    /// app. Launched by the pick-up, it waits for the window as a link does.
    static func continuePage(_ url: URL, space: String?) {
        guard deliver != nil, let target = MainActor.assumeIsolated({ BrowserWindows.shared.activeBrowser ?? browser }) else {
            take(url)
            return
        }
        arrived = true
        MainActor.assumeIsolated {
            Headless.show(.person)
            if target.prefs.usesSpaces, let space,
               let there = target.spaces.first(where: { ContinuePage.sameSpace($0.id.uuidString, space) }) {
                target.switchSpace(to: there.id)
            } else if let home = LinkRoutes.shared.space(for: url, in: target) {
                target.switchSpace(to: home)
            }
            target.pickUp(url)
            showBrowser(target)
            NSApp.activate()
        }
    }

    @MainActor
    static func requestNewTab() {
        Headless.show(.person)
        if let target = BrowserWindows.shared.activeBrowser ?? browser {
            target.newTab()
            showBrowser(target)
            NSApp.activate()
        } else {
            waitingNewTabs += 1
            DispatchQueue.main.async { summon() }
        }
    }

    /// A link that launches the app arrives as an Apple Event, taken above,
    /// and SwiftUI, seeing a launch that came to open something rather than
    /// a plain one, leaves its window for that event to open. It never sees
    /// the event, so nothing opened it: every link clicked in another app
    /// while yab was closed launched it with no window and the page
    /// nowhere. SwiftUI's delegate is asked instead for what a plain launch
    /// gets, its window; a single window, so asking twice can't make two.
    @MainActor
    private static func summon() {
        guard deliver == nil, window == nil, !summoned else { return }
        summoned = true
        _ = NSApp.delegate?.applicationOpenUntitledFile?(NSApp)
    }

    /// Yab's community: the group chat on X the site's changelog links to.
    static let community = URL(string: "https://x.com/i/chat/group_join/g2108389056413618447/Tmr5OvF8Rx")!

    /// A web page Settings links to, in a tab of Yab's own, keeping the
    /// Settings window and its place for the next change. Not through
    /// NSWorkspace: that handed the address to the Mac's browser, Yab itself,
    /// which took it back as a link from another app, into a small window: Launch Services waited
    /// for on the main thread, then a second page made (#372, a 7 s stall
    /// with 360 tabs on 0.35.10). With Yab not the Mac's browser, the page
    /// opened in another one.
    @MainActor
    static func openFromSettings(_ url: URL, in source: Browser? = nil) {
        guard let target = source ?? browser else {
            NSWorkspace.shared.open(url)
            return
        }
        Headless.show(.person)
        _ = target.open(url, foreground: true)
        showBrowser(target)
        NSApp.activate()
    }

    /// The field, the Help menu, and the About page all come here: a sheet on the
    /// window you are in that already knows what build this is, and sends
    /// only when Send is pressed. A build with no site gets a draft in Mail.
    static func writeFeedback(on window: NSWindow? = nil) {
        // A sheet here that sends straight to the site (Feedback.swift).
        if Updater.site != nil {
            MainActor.assumeIsolated { FeedbackSheet.show(on: window) }
            return
        }
        // A build with no site to write to: a letter instead.
        var text = URLComponents()
        text.scheme = "mailto"
        text.path = "hello@serafimlabs.io"
        text.queryItems = [
            URLQueryItem(name: "subject", value: "Yab \(Updater.version) (\(Updater.build)) feedback"),
            URLQueryItem(name: "body", value: "\n\n–\nYab \(Updater.version) (\(Updater.build)) on macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"),
        ]
        guard let url = text.url else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - being the browser

    private static let probe = URL(string: "https://example.com")!

    /// True when this app is where links from other apps go.
    ///
    /// Kept, not asked each time: LaunchServices takes 10 to 30 ms of the
    /// main thread to answer, and the Yab menu's commands ask it on every
    /// pass of the app's body, which a tab switch or a woken tab makes
    /// (feedback #337, #347: about 100 ms of the main thread in 30 s of
    /// switching tabs). Asked again after Yab comes back to the front,
    /// where a change made in System Settings shows, and after Yab asked
    /// to be the default.
    static var isDefault: Bool {
        defaultLock.lock()
        if let known = knownDefault {
            defaultLock.unlock()
            return known
        }
        defaultLock.unlock()
        let answer = NSWorkspace.shared.urlForApplication(toOpen: probe)
            .map { $0.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL } ?? false
        defaultLock.lock()
        knownDefault = answer
        if defaultWatch == nil {
            defaultWatch = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                                                  object: nil, queue: nil) { _ in forgetDefault() }
        }
        defaultLock.unlock()
        return answer
    }

    private static let defaultLock = NSLock()
    nonisolated(unsafe) private static var knownDefault: Bool?
    nonisolated(unsafe) private static var defaultWatch: NSObjectProtocol?

    /// The next `isDefault` asks LaunchServices again.
    static func forgetDefault() {
        defaultLock.lock()
        knownDefault = nil
        defaultLock.unlock()
    }

    /// Asks macOS to send http and https here. The system puts up its own
    /// confirmation; the answer arrives through `done`, on the main thread.
    /// Once it is yes, a web page double-clicked in the Finder opens here
    /// too, as it does in every other browser that is the default: only
    /// then, so saying no to the links doesn't hand over the files.
    @MainActor private static var defaultChange: DefaultBrowserChange?
    @MainActor private static var defaultAnswers: [(Bool) -> Void] = []

    @MainActor static func becomeDefault(_ done: @escaping (Bool) -> Void) {
        defaultAnswers.append(done)
        guard defaultChange == nil else { return }
        let app = Bundle.main.bundleURL
        let change = DefaultBrowserChange(current: { scheme in
            guard let url = URL(string: "\(scheme)://example.com"),
                  let handler = NSWorkspace.shared.urlForApplication(toOpen: url) else { return false }
            return handler.standardizedFileURL == app.standardizedFileURL
        }, request: { scheme, answered in
            NSWorkspace.shared.setDefaultApplication(at: app, toOpenURLsWithScheme: scheme) { error in
                DispatchQueue.main.async { answered(error == nil) }
            }
        }, html: {
            NSWorkspace.shared.setDefaultApplication(at: app, toOpen: .html) { _ in }
        }, completion: { worked in
            forgetDefault()
            defaultChange = nil
            let answers = defaultAnswers
            defaultAnswers = []
            answers.forEach { $0(worked) }
        })
        defaultChange = change
        change.start()
    }
}
