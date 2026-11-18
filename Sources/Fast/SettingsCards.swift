import AppKit
import Combine
import SwiftUI

// Settings' cards and questions stand in a window of their own over the
// Settings window, not inside it: Connect's steps, an extension's long
// list of powers or the snippet editor are taller than Settings is at its
// usual 540, and drawn inside it they were cut off at its foot. The panel
// is a clear column the height of the screen over Settings, the card in it
// at Settings' middle, kept on the screen when taller; Settings under it is
// dimmed (SettingsVeil) and held still until the card goes.

@MainActor
final class SettingsCards {
    static let shared = SettingsCards()
    nonisolated(unsafe) private static weak var embeddedWindow: NSWindow?

    /// Where the card stands in the panel: Settings' middle, from the
    /// panel's, and how tall the panel is.
    final class Spot: ObservableObject {
        @Published var offset: CGFloat = 0
        @Published var height: CGFloat = 0
    }

    let spot = Spot()
    private var panel: SettingsCardPanel?
    private weak var parent: NSWindow?
    private var watch: AnyCancellable?
    private var placementWatch: AnyCancellable?
    private var shown = false

    /// A card or a question of Settings' own is up.
    var up: Bool { Questions.shared.current?.place == .settings || closer != nil }

    /// Settings on screen, where a question of its own can be seen.
    var showing: Bool { parent?.isVisible == true }
    var inTab: Bool { Self.embeddedWindow != nil }

    /// Takes down the card up, a click outside it or the veil's: never a
    /// question, which waits for its answer.
    var closer: (() -> Void)? {
        if SiteEditing.shared.draft != nil { return { SiteEditing.shared.close() } }
        if QuickActionEditing.shared.action != nil { return { QuickActionEditing.shared.close() } }
        if ShieldSourceEditing.shared.draft != nil { return { ShieldSourceEditing.shared.close() } }
        if LinkRouteEditing.shared.draft != nil { return { LinkRouteEditing.shared.close() } }
        if EngineSiteEditing.shared.draft != nil { return { EngineSiteEditing.shared.close() } }
        if RoutineEditing.shared.card != nil { return { RoutineEditing.shared.closeCard() } }
        if #available(macOS 15.4, *), BlockEditing.shared.draft != nil { return { BlockEditing.shared.close() } }
        if AwakeSiteEditing.shared.draft != nil { return { AwakeSiteEditing.shared.close() } }
        if PasswordManagers.Connections.shared.card != nil { return { PasswordManagers.Connections.shared.card = nil } }
        if SnippetEditing.shared.card != nil || SnippetEditing.shared.bring != nil { return { SnippetEditing.shared.close() } }
        return nil
    }

    /// Every card's state, for the panel to come and go with them.
    private var changes: AnyPublisher<Void, Never> {
        var all: [AnyPublisher<Void, Never>] = [
            Questions.shared.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            SiteEditing.shared.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            QuickActionEditing.shared.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            ShieldSourceEditing.shared.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            LinkRouteEditing.shared.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            EngineSiteEditing.shared.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            RoutineEditing.shared.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            AwakeSiteEditing.shared.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            PasswordManagers.Connections.shared.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            SnippetEditing.shared.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
        ]
        if #available(macOS 15.4, *) {
            all.append(BlockEditing.shared.objectWillChange.map { _ in () }.eraseToAnyPublisher())
        }
        return Publishers.MergeMany(all).eraseToAnyPublisher()
    }

    /// Made with the Settings window, as its child.
    func attach(to window: NSWindow, browser: Browser) {
        parentClosed()
        panel?.close()
        watch = nil
        parent = window
        Self.embeddedWindow = window is SettingsFrame ? nil : window
        let panel = SettingsCardPanel(
            contentRect: window.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.animationBehavior = .none
        let host = NSHostingView(rootView: SettingsCardStack(browser: browser, spot: spot))
        host.sizingOptions = []
        panel.contentView = host
        self.panel = panel
        placementWatch = Publishers.MergeMany([
            NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSWindow.didChangeScreenNotification
        ].map { NotificationCenter.default.publisher(for: $0, object: window) })
            .sink { [weak self] _ in self?.place() }
        // After the change is published, once the stores hold the new state.
        watch = changes.receive(on: DispatchQueue.main).sink { [weak self] in self?.update() }
    }

    /// The column over Settings: Settings' width, the screen's height.
    func place() {
        guard let panel, let parent else { return }
        let screen = (parent.screen ?? NSScreen.main)?.visibleFrame ?? parent.frame
        let frame = NSRect(x: parent.frame.minX, y: screen.minY, width: parent.frame.width, height: screen.height)
        if panel.frame != frame { panel.setFrame(frame, display: shown) }
        let offset = frame.midY - parent.frame.midY
        if spot.offset != offset { spot.offset = offset }
        if spot.height != frame.height { spot.height = frame.height }
    }

    /// Settings back on screen (opened again, out of the Dock): the card
    /// that is up shown over it again, since nothing about the card changed.
    func refresh() { update() }

    private func update() {
        guard let panel, let parent else { return }
        let up = up && parent.isVisible
        guard up != shown else { return }
        shown = up
        if up {
            place()
            parent.addChildWindow(panel, ordered: .above)
            panel.orderFront(nil)
            panel.makeKey()
        } else {
            parent.removeChildWindow(panel)
            panel.orderOut(nil)
            if NSApp.isActive { parent.makeKey() }
        }
    }

    /// Settings going away takes its card with it, and answers its
    /// question no. A card kept is shown again with Settings (refresh).
    func parentClosed() {
        Self.embeddedWindow = nil
        guard let panel else { return }
        shown = false
        parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        Questions.shared.settingsClosed()
    }

    /// A tab put away must stop presenting cards over its still-visible browser.
    func detach() {
        parentClosed()
        watch = nil
        placementWatch = nil
        panel?.close()
        panel = nil
        parent = nil
    }

    /// The panel or Settings itself: both answer Settings' questions.
    nonisolated static func owns(_ window: NSWindow?) -> Bool { window is SettingsFrame || window is SettingsCardPanel || (window != nil && window === embeddedWindow) }
}

/// Takes the keyboard for its fields and Escape, without a title bar.
final class SettingsCardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// ⌘W closes Settings, as it does with no card up.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if Keymap.shared.matches(event, .closeTab), parent != nil {
            SettingsWindow.shared.hide()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// Every card Settings asks with, in the panel at Settings' middle. A
/// click beside the card takes it down, as the dimming's did.
private struct SettingsCardStack: View {
    let browser: Browser
    @ObservedObject var spot: SettingsCards.Spot
    @State private var tall: CGFloat = 0

    var body: some View {
        // The card's middle at Settings' middle, kept 12 inside the screen.
        let room = max(0, (spot.height - tall) / 2 - 12)
        let offset = min(max(spot.offset, -room), room)
        ZStack {
            Color.black.opacity(SettingsCards.shared.inTab && SettingsCards.shared.closer != nil ? 0.12 : 0.001)
                .contentShape(Rectangle())
                .onTapGesture { SettingsCards.shared.closer?() }
            ZStack {
                SettingsQuestionLayer(room: spot.height - 48)
                SiteCardLayer()
                QuickActionCardLayer()
                LinkRouteCardLayer()
                EngineSiteCardLayer()
                ShieldSourceCardLayer()
                RoutineCardLayer(browser: browser)
                if #available(macOS 15.4, *) { BlockCardLayer() }
                AwakeSiteCardLayer()
                PasswordCardLayer()
                SnippetCardLayer()
            }
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { tall = $0 }
            .offset(y: offset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
}

/// Over Settings while a card is up: dimmed for a card, clear for a
/// question, and taking every click either way.
struct SettingsVeil: View {
    @ObservedObject private var questions = Questions.shared
    @ObservedObject private var site = SiteEditing.shared
    @ObservedObject private var quick = QuickActionEditing.shared
    @ObservedObject private var shield = ShieldSourceEditing.shared
    @ObservedObject private var link = LinkRouteEditing.shared
    @ObservedObject private var engine = EngineSiteEditing.shared
    @ObservedObject private var routine = RoutineEditing.shared
    @ObservedObject private var awake = AwakeSiteEditing.shared
    @ObservedObject private var passwords = PasswordManagers.Connections.shared
    @ObservedObject private var snippets = SnippetEditing.shared
    @State private var tick = 0

    var body: some View {
        let cards = SettingsCards.shared
        ZStack {
            if cards.closer != nil {
                Color.black.opacity(0.12)
                    .contentShape(Rectangle())
                    .onTapGesture { cards.closer?() }
                    .transition(.asymmetric(insertion: .opacity.animation(Motion.arrive), removal: .identity))
            } else if questions.current?.place == .settings {
                Color.clear.contentShape(Rectangle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(BlockWatch(tick: $tick))
    }
}

/// The extension's Add Site… card is only on macOS 15.4 and later.
private struct BlockWatch: ViewModifier {
    @Binding var tick: Int

    func body(content: Content) -> some View {
        if #available(macOS 15.4, *) {
            content.onReceive(BlockEditing.shared.objectWillChange) { _ in DispatchQueue.main.async { tick += 1 } }
        } else {
            content
        }
    }
}
