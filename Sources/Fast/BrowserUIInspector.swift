import AppKit
import SwiftUI

enum UIInspectorPlacement: String, CaseIterable {
    case docked = "Docked"
    case drawer = "Drawer"
    case floating = "Floating"
    case detached = "Detached window"
}

struct UIInspectorSource: Equatable {
    let file: String
    let line: Int

    init(file: String = #filePath, line: Int = #line) {
        self.file = file
        self.line = line
    }

    var relativePath: String {
        if let sources = file.range(of: "/Sources/", options: .backwards) { return String(file[file.index(after: sources.lowerBound)...]) }
        return URL(fileURLWithPath: file).lastPathComponent
    }

    var display: String { "\(relativePath):\(line)" }

    @MainActor func open(_ url: URL) {
        let workspace = NSWorkspace.shared
        let preferred = workspace.urlForApplication(toOpen: url)
        // Editors that support a line argument use their own bundled CLI.
        let editors = [
            ("com.microsoft.VSCode", "Contents/Resources/app/bin/code"),
            ("com.todesktop.230313mzl4w4u92", "Contents/Resources/app/bin/cursor")
        ]
        let preferredID = preferred.flatMap { Bundle(url: $0)?.bundleIdentifier }
        let ordered = editors.filter { $0.0 == preferredID } + editors.filter { $0.0 != preferredID }
        for (identifier, tool) in ordered {
            guard let app = workspace.urlForApplication(withBundleIdentifier: identifier) else { continue }
            if Self.launch(appending: tool, to: app, arguments: ["--goto", "\(url.path):\(line)"], fallback: url) { return }
        }
        if preferred?.lastPathComponent == "Xcode.app",
           Self.launch(appending: "usr/bin/xed", to: URL(fileURLWithPath: "/"),
                       arguments: ["--line", String(line), url.path], fallback: url) { return }
        workspace.open(url)
    }

    private static func launch(appending tool: String, to root: URL, arguments: [String], fallback: URL) -> Bool {
        let executable = root.appendingPathComponent(tool)
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { return false }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.terminationHandler = { process in
            guard process.terminationStatus != 0 else { return }
            DispatchQueue.main.async { NSWorkspace.shared.open(fallback) }
        }
        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }
}

struct UIInspectorStyle: Equatable {
    var group: String
    var name: String
    var value: String
    var swatch: NSColor?

    init(_ group: String, _ name: String, _ value: String, swatch: NSColor? = nil) {
        self.group = group
        self.name = name
        self.value = value
        self.swatch = swatch
    }

    static func points(_ value: CGFloat) -> String {
        Double(value).formatted(FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...1))) + " pt"
    }

    static func size(_ size: CGSize) -> String {
        "\(points(size.width)) × \(points(size.height))"
    }
}

struct UIInspectorNode: Equatable {
    var component: String
    var label: String?
    var source: UIInspectorSource
    var logicalParent: String?
    var pickable = true
    var styles: [UIInspectorStyle] = []
}

struct UIInspectorID: Hashable {
    let view: UUID
    let item: String?
}

struct UIInspectorEntry: Identifiable, Equatable {
    let id: UIInspectorID
    let node: UIInspectorNode
    let size: CGSize
    let children: [UIInspectorEntry]
}

private struct UIInspectorParent: EnvironmentKey {
    static let defaultValue: UIInspectorID? = nil
}

private extension EnvironmentValues {
    var uiInspectorParent: UIInspectorID? {
        get { self[UIInspectorParent.self] }
        set { self[UIInspectorParent.self] = newValue }
    }
}

extension View {
    /// Attach source and styling information at the view that owns it.
    /// Native probes are created only during an inspection session.
    func uiInspectable(item: String? = nil, _ node: @autoclosure @escaping () -> UIInspectorNode) -> some View {
        modifier(UIInspectable(item: item, node: node))
    }
}

private struct UIInspectable: ViewModifier {
    let item: String?
    let node: () -> UIInspectorNode
    @State private var viewID = UUID()
    @Environment(\.uiInspectorParent) private var parent

    func body(content: Content) -> some View {
        let id = UIInspectorID(view: viewID, item: item)
        let enabled = BrowserUIInspector.shared.enabled
        content
            .transformEnvironment(\.uiInspectorParent) {
                if enabled { $0 = id }
            }
            .background {
                if enabled {
                    UIInspectorMarker(id: id, parent: parent, node: node())
                }
            }
    }
}

private struct UIInspectorMarker: NSViewRepresentable {
    let id: UIInspectorID
    let parent: UIInspectorID?
    let node: UIInspectorNode

    func makeNSView(context: Context) -> UIInspectorProbe { UIInspectorProbe() }

    func updateNSView(_ view: UIInspectorProbe, context: Context) {
        view.id = id
        view.parent = parent
        view.node = node
    }
}

final class UIInspectorProbe: NSView {
    var id: UIInspectorID?
    var parent: UIInspectorID?
    var node: UIInspectorNode?
    var isPanel = false

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        BrowserUIInspector.shared.register(self)
    }

    var boundsInWindow: CGRect { convert(bounds, to: nil) }

    var visibleBoundsInWindow: CGRect {
        guard !isHiddenOrHasHiddenAncestor else { return .null }
        var view: NSView? = self
        while let current = view {
            guard current.alphaValue > 0.01 else { return .null }
            view = current.superview
        }
        // A view that lets its content overflow can report a visibleRect
        // larger than itself. Only the part inside this probe is pickable.
        return convert(visibleRect.intersection(bounds), to: nil)
    }
}

@MainActor @Observable
final class BrowserUIInspector: NSObject, NSWindowDelegate {
    static let shared = BrowserUIInspector()

    private(set) var enabled = false
    private(set) var picking = false
    private(set) var placement: UIInspectorPlacement = .docked
    private(set) var tree: [UIInspectorEntry] = []
    private(set) var selected: UIInspectorID?
    private var owner: Browser?
    @ObservationIgnored private weak var target: NSWindow?
    @ObservationIgnored private var detached: NSWindow?
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var refresh: Timer?
    @ObservationIgnored private var hover: UIInspectorID?
    @ObservationIgnored private let probes = NSHashTable<UIInspectorProbe>.weakObjects()
    @ObservationIgnored private let outline = UIInspectorOutline()
    @ObservationIgnored private var sourceFolder: URL?

    func isOpen(for browser: Browser) -> Bool { enabled && owner === browser }

    func toggle(in browser: Browser) {
        if isOpen(for: browser) {
            close()
        } else if let window = BrowserWindows.shared.window(for: browser) {
            close()
            owner = browser
            target = window
            enabled = true
            startPicking()
            if placement == .detached { showDetached(for: browser) }
            refresh = Timer.scheduledTimer(withTimeInterval: 1.0 / 15, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.update() }
            }
        }
    }

    func register(_ probe: UIInspectorProbe) {
        if probe.window != nil { probes.add(probe) } else { probes.remove(probe) }
    }

    func startPicking() {
        guard let target else { return }
        picking = true
        target.acceptsMouseMovedEvents = true
        owner?.glance.drop()
        attachOutline(to: target)
        outline.updateTrackingAreas()
        if monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.cancelPick(with: event) == true ? nil : event
            }
        }
    }

    func select(_ id: UIInspectorID) {
        selected = id
        stopPicking()
        update()
    }

    func move(to placement: UIInspectorPlacement) {
        guard let owner, self.placement != placement else { return }
        if self.placement == .detached { dismissDetached() }
        self.placement = placement
        if placement == .detached { showDetached(for: owner) }
    }

    func close(for browser: Browser) {
        if owner === browser { close() }
    }

    func close() {
        dismissDetached()
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        refresh?.invalidate()
        refresh = nil
        outline.removeFromSuperview()
        outline.show(nil)
        enabled = false
        picking = false
        tree = []
        hover = nil
        selected = nil
        owner = nil
        target = nil
    }

    func openSource(_ source: UIInspectorSource) {
        let original = URL(fileURLWithPath: source.file)
        let packagedFolder = Bundle.main.object(forInfoDictionaryKey: "YabSourceCheckout") as? String
        let folder = sourceFolder ?? packagedFolder.map { URL(fileURLWithPath: $0, isDirectory: true) }
        let candidates = [folder?.appendingPathComponent(source.relativePath), original]
        if let url = candidates.compactMap({ $0 }).first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            source.open(url)
            return
        }
        guard let window = detached ?? target else { return }
        let panel = NSOpenPanel()
        panel.title = "Locate Yab Source"
        panel.prompt = "Choose Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let folder = panel.url else { return }
            let file = folder.appendingPathComponent(source.relativePath)
            if FileManager.default.fileExists(atPath: file.path) {
                self?.sourceFolder = folder
                source.open(file)
            } else {
                let alert = NSAlert()
                alert.messageText = "Source File Unavailable"
                alert.informativeText = source.display
                alert.beginSheetModal(for: window)
            }
        }
    }

    func cancelPick(with event: NSEvent) -> Bool {
        guard picking, event.type == .keyDown, event.keyCode == 53,
              event.window === target || event.window === detached else { return false }
        stopPicking()
        update()
        return true
    }

    private func stopPicking() {
        picking = false
        hover = nil
        outline.updateTrackingAreas()
        target?.invalidateCursorRects(for: outline)
    }

    func ownsPointer(in window: NSWindow?) -> Bool { picking && window === target }

    func picks(at point: CGPoint, in window: NSWindow?) -> Bool {
        ownsPointer(in: window) && !panelFrame.contains(point)
    }

    func point(at point: CGPoint, commit: Bool = false) {
        guard picks(at: point, in: target) else { return }
        aim(at: point)
        if commit, let hover { select(hover) }
        else { updateOutline() }
    }

    func clearHover() {
        hover = nil
        updateOutline()
    }

    private var windowProbes: [UIInspectorProbe] { probes.allObjects.filter { $0.window === target } }

    private var panelFrame: CGRect {
        windowProbes.first { $0.isPanel }?.visibleBoundsInWindow ?? .null
    }

    private func aim(at point: CGPoint) {
        hover = windowProbes.filter {
            $0.node?.pickable == true && $0.visibleBoundsInWindow.contains(point)
        }.min {
            let first = $0.visibleBoundsInWindow
            let second = $1.visibleBoundsInWindow
            return first.width * first.height < second.width * second.height
        }?.id
    }

    private func update() {
        guard let target else { close(); return }
        guard target.isVisible, !target.isMiniaturized else { outline.show(nil); return }
        if picking {
            let point = target.mouseLocationOutsideOfEventStream
            if panelFrame.contains(point) || !NSApp.isActive {
                hover = nil
            } else {
                aim(at: point)
            }
        }
        if let selected { updateTree(around: selected) }
        updateOutline()
    }

    private func updateTree(around selected: UIInspectorID) {
        let visible = windowProbes.filter { $0.id != nil && !$0.visibleBoundsInWindow.isEmpty }
        let byID = Dictionary(visible.compactMap { probe in probe.id.map { ($0, probe) } },
                              uniquingKeysWith: { first, _ in first })
        guard let picked = byID[selected] else { return }
        // SwiftUI hosting roots, including the recycled tab cells, may
        // supply an explicit component parent across the AppKit boundary.
        func parent(of probe: UIInspectorProbe) -> UIInspectorID? {
            if let parent = probe.parent, byID[parent] != nil { return parent }
            guard let name = probe.node?.logicalParent else { return nil }
            let center = CGPoint(x: probe.boundsInWindow.midX, y: probe.boundsInWindow.midY)
            return visible.first {
                $0.node?.component == name && $0.visibleBoundsInWindow.contains(center)
            }?.id
        }
        let children = Dictionary(grouping: visible, by: parent(of:))
        var root = picked
        while let next = parent(of: root), let ancestor = byID[next] {
            root = ancestor
        }
        func entry(_ probe: UIInspectorProbe) -> UIInspectorEntry? {
            guard let id = probe.id, let node = probe.node else { return nil }
            let ordered = (children[id] ?? []).sorted {
                let first = $0.boundsInWindow
                let second = $1.boundsInWindow
                let firstRow = (first.midY / 4).rounded()
                let secondRow = (second.midY / 4).rounded()
                if firstRow != secondRow { return firstRow > secondRow }
                if first.minX != second.minX { return first.minX < second.minX }
                return ($0.node?.component ?? "") < ($1.node?.component ?? "")
            }
            return UIInspectorEntry(id: id, node: node,
                                    size: probe.bounds.size, children: ordered.compactMap(entry))
        }
        let next = [entry(root)].compactMap { $0 }
        if tree != next { tree = next }
    }

    private func attachOutline(to window: NSWindow) {
        guard let content = window.contentView, outline.superview !== content else { return }
        outline.frame = content.bounds
        outline.autoresizingMask = [.width, .height]
        content.addSubview(outline, positioned: .above, relativeTo: nil)
    }

    private func updateOutline() {
        guard let target else { return }
        attachOutline(to: target)
        let id = picking ? hover : selected
        let frame = id.flatMap { id in windowProbes.first { $0.id == id }?.visibleBoundsInWindow }
        if let frame, !frame.isEmpty { outline.show(outline.convert(frame, from: nil)) }
        else { outline.show(nil) }
    }

    func benchState() -> [String: Any] {
        [
            "open": enabled,
            "picking": picking,
            "placement": placement.rawValue,
            "target": target?.windowNumber ?? 0,
            "detached": detached?.windowNumber ?? 0,
            "panel": panelFrame.isNull ? "" : NSStringFromRect(panelFrame),
            "selected": windowProbes.first { $0.id == selected }?.node?.component ?? "",
            "hover": windowProbes.first { $0.id == hover }?.node?.component ?? "",
            "probes": windowProbes.compactMap { probe -> [String: String]? in
                guard let node = probe.node else { return nil }
                let visible = probe.visibleBoundsInWindow
                return [
                    "component": node.component,
                    "label": node.label ?? "",
                    "bounds": NSStringFromRect(probe.boundsInWindow),
                    "visible": visible.isNull ? "" : NSStringFromRect(visible)
                ]
            }
        ]
    }

    private func showDetached(for browser: Browser) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 445, height: 690),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Browser UI Inspector"
        window.identifier = NSUserInterfaceItemIdentifier("BrowserUIInspector")
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 300, height: 300)
        window.delegate = self
        window.contentView = WindowHosting.content(UIInspectorDetached(browser: browser))
        window.center()
        detached = window
        window.makeKeyAndOrderFront(nil)
    }

    private func dismissDetached() {
        guard let window = detached else { return }
        detached = nil
        window.delegate = nil
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === detached else { return }
        detached = nil
        close()
    }

    static func browser(for window: NSWindow?) -> Browser? {
        guard let window, window === shared.detached else { return nil }
        return shared.owner
    }
}

private final class UIInspectorOutline: NSView {
    private var selection: CGRect?
    private var tracking: NSTrackingArea?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview else { return nil }
        let local = convert(point, from: superview)
        let location = convert(local, to: nil)
        guard bounds.contains(local), BrowserUIInspector.shared.picks(at: location, in: window) else { return nil }
        return self
    }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        guard BrowserUIInspector.shared.ownsPointer(in: window) else { tracking = nil; return }
        let area = NSTrackingArea(rect: .zero, options: [.inVisibleRect, .activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .cursorUpdate],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func cursorUpdate(with event: NSEvent) {
        if BrowserUIInspector.shared.picks(at: event.locationInWindow, in: window) { NSCursor.crosshair.set() }
        else { super.cursorUpdate(with: event) }
    }

    override func mouseMoved(with event: NSEvent) { BrowserUIInspector.shared.point(at: event.locationInWindow) }
    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseExited(with event: NSEvent) { BrowserUIInspector.shared.clearHover() }
    override func mouseDown(with event: NSEvent) { BrowserUIInspector.shared.point(at: event.locationInWindow, commit: true) }
    override func mouseUp(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func rightMouseUp(with event: NSEvent) {}
    override func otherMouseDown(with event: NSEvent) {}
    override func otherMouseUp(with event: NSEvent) {}

    func show(_ rect: CGRect?) {
        guard rect != selection else { return }
        selection = rect
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let selection else { return }
        let tint = NSColor.systemBlue
        let outline = NSBezierPath(roundedRect: selection.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
        tint.withAlphaComponent(0.12).setFill()
        outline.fill()
        tint.setStroke()
        outline.stroke()

        let text = UIInspectorStyle.size(selection.size) as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attributes)
        let label = CGRect(x: min(selection.minX, max(0, bounds.maxX - size.width - 12)),
                           y: min(selection.maxY + 4, bounds.maxY - size.height - 9),
                           width: size.width + 12, height: size.height + 6)
        tint.setFill()
        NSBezierPath(roundedRect: label, xRadius: 4, yRadius: 4).fill()
        text.draw(at: CGPoint(x: label.minX + 6, y: label.minY + 3), withAttributes: attributes)
    }
}
