import SwiftUI

/// Keep the page's overlays outside ContentView's already large split layout.
/// Separate view bodies bound the generic types SwiftUI initializes on first open.
struct PageContent: View {
    @ObservedObject var browser: Browser
    /// Room made beside the page (SplitPreview): held, WebKit following.
    @ObservedObject var preview: SplitPreview
    @ObservedObject var tab: Tab
    let corner: CGFloat
    let showBar: Bool
    let front: Bool

    var body: some View {
        Page(tab: tab, corner: corner, flatTop: showBar, holding: browser.reshaping || preview.moving,
             following: browser.followingSize || preview.moving, tracking: browser.trackingSize,
             protectsViewportGrowth: browser.devMoving,
             sidebarPin: browser.sidebarPins,
             paned: (browser.inMail && MailPage.isMail(tab.address)))
            .overlay { SelectionLayer(commands: browser.selectionCommands, tab: tab) }
            .overlay { PageMail(browser: browser, tab: tab, corner: corner, flatTop: showBar) }
            .overlay(alignment: .topLeading) { PageSuggestions(browser: browser, tab: tab) }
            .overlay { PagePointer(tab: tab) }
            .overlay(alignment: .top) {
                if browser.inMail, MailChat.isAgents(tab) { MailBackCrumb(browser: browser).padding(.top, 12) }
            }
            .overlay(alignment: .bottom) {
                GeometryReader { page in
                    PageFoot(availableWidth: page.size.width, tab: tab, selection: browser.selectionCommands)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            }
            .overlay(alignment: .topTrailing) {
                if front {
                    BoostTrialView(tab: tab)
                    UserscriptCard(browser: browser, tab: tab)
                }
            }
            .animation(Motion.quick, value: browser.suggesting)
            .animation(Motion.quick, value: browser.fieldPlate)
            .animation(Motion.quick, value: browser.agentFilling)
            .animation(Motion.quick, value: browser.walletList)
            .animation(Motion.quick, value: browser.codeList?.codes)
    }
}

/// Mail over its page: the card's edge is the pane's, cut on the card's own
/// outline, square under the address bar (the page steps in, see
/// StageView.covered).
private struct PageMail: View {
    @ObservedObject var browser: Browser
    @ObservedObject var tab: Tab
    let corner: CGFloat
    let flatTop: Bool

    var body: some View {
        if browser.inMail, MailPage.isMail(tab.address) {
            // When mail's pane is first asked for in a switch (evals/mail/enter_trace.py).
            let _ = SwitchMeter.mark("mail pane")
            MailPane()
                .clipShape(PageCut(corner: corner, flatTop: flatTop))
        }
    }
}

struct PageSuggestions: View {
    @ObservedObject var browser: Browser
    let tab: Tab
    /// The snippets by the name typed after ";" (PageSnippets).
    @ObservedObject var snippets = PageSnippets.shared
    /// Native panels keep clicks outside the actual list on the page.
    var sized: ((CGSize) -> Void)? = nil

    var body: some View {
        Group {
            if let filling = browser.agentFilling, filling.tab == tab.id {
                AgentFillingList(browser: browser, tab: tab, filling: filling).transition(.opacity)
            } else if let asked = browser.suggesting, asked.tab == tab.id {
                AccountList(browser: browser, asked: asked).transition(.opacity)
            } else if let list = browser.codeList, list.tab == tab.id {
                CodeList(browser: browser, list: list).transition(.opacity)
            } else if let list = browser.walletList, list.tab == tab.id {
                WalletList(browser: browser, list: list).transition(.opacity)
            } else if let call = snippets.call, call.tab == tab.id {
                PageSnippetList(snippets: snippets, call: call).transition(.opacity)
            }
        }
        .animation(Motion.quick, value: snippets.call?.rows.map(\.id))
        .onGeometryChange(for: CGSize.self) { $0.size } action: { sized?($0) }
        // Yab's plate in the box, over where the managers' icons were.
        .overlay(alignment: .topLeading) {
            if let plate = browser.fieldPlate, plate.tab == tab.id, browser.agentFilling == nil {
                FieldPlateView(browser: browser, plate: plate).transition(.opacity)
            }
        }
    }
}

/// A native peek uses the same lists as the page's SwiftUI overlay. The
/// transparent room belongs to WebKit, only the measured list takes clicks.
final class PageSuggestionsHost: NSHostingView<PageSuggestionsPane> {
    private weak var browser: Browser?
    private let tab: Tab
    private var listSize: CGSize = .zero

    convenience init(browser: Browser, tab: Tab) {
        self.init(rootView: PageSuggestionsPane(browser: browser, tab: tab))
    }

    required init(rootView: PageSuggestionsPane) {
        self.browser = rootView.browser
        self.tab = rootView.tab
        super.init(rootView: rootView)
        isFlipped = true
        self.rootView.sized = { [weak self] size in self?.listSize = size }
        sizingOptions = []
        safeAreaRegions = []
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let browser, !tab.gone, !tab.asleep else { return nil }
        let spot: CGRect?
        if let list = browser.suggesting, list.tab == tab.id {
            spot = list.spot
        } else if let list = browser.codeList, list.tab == tab.id {
            spot = list.spot
        } else if let list = browser.walletList, list.tab == tab.id {
            spot = list.spot
        } else if let call = PageSnippets.shared.call, call.tab == tab.id {
            spot = call.spot
        } else {
            spot = nil
        }
        let at = convert(point, from: superview)
        if let plate = browser.fieldPlate, plate.tab == tab.id, plate.frame.contains(at) { return super.hitTest(point) }
        guard let spot else { return nil }
        let rect = CGRect(x: spot.minX, y: spot.maxY + 6,
                          width: listSize.width, height: listSize.height)
        guard rect.contains(at) else { return nil }
        return super.hitTest(point)
    }
}

struct PageSuggestionsPane: View {
    @ObservedObject var browser: Browser
    let tab: Tab
    var sized: ((CGSize) -> Void)? = nil

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear.allowsHitTesting(false)
            PageSuggestions(browser: browser, tab: tab, sized: sized)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

extension Browser {
    /// A list answers only the keys pressed in its own page, including a
    /// small window or a peek rather than the browser's selected row tab.
    func autofillKey(_ event: NSEvent, on tab: Tab) -> Bool {
        guard offersAutofill(tab), let web = tab.builtPage, event.window === web.window,
              event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
        else { return false }
        if suggesting?.tab == tab.id {
            switch event.keyCode {
            case 125: moveChoice(1)
            case 126: moveChoice(-1)
            case 36, 76: return chooseLit()
            case 53: dropChoice()
            default: return false
            }
        } else if codeList?.tab == tab.id {
            switch event.keyCode {
            case 125: moveCode(1)
            case 126: moveCode(-1)
            case 36, 76: return pickLitCode()
            case 53: codeList = nil; codeWatch.stop()
            default: return false
            }
        } else if walletList?.tab == tab.id {
            switch event.keyCode {
            case 125: moveWallet(1)
            case 126: moveWallet(-1)
            case 36, 76: return chooseWalletLit()
            case 53: dropWallet()
            default: return false
            }
        } else {
            return false
        }
        return true
    }
}

/// A half's content given the side it is laid in, room made beside the lone
/// page in front included (SplitPreview): watched here, so making room lays
/// out only the half, not the window.
struct Sided<Content: View>: View {
    @ObservedObject var preview: SplitPreview
    let laid: Side
    let alone: Bool
    /// The side, and whether the half's band is to be built ahead.
    @ViewBuilder let content: (Side, Bool) -> Content

    var body: some View { content(preview.side(laid, alone: alone), alone && preview.warm) }
}

/// The paper under a page, carried with it while room is made beside it.
struct RoomPaper: View {
    @ObservedObject var preview: SplitPreview
    let corner: CGFloat
    let dark: Bool
    let band: PaperBand?
    let moving: Bool

    var body: some View { Paper(corner: corner, dark: dark, band: band, moving: moving || preview.moving) }
}
