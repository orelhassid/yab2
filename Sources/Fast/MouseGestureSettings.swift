import SwiftUI

struct MouseGestureSettings: View {
    @AppStorage(MouseMappings.enabledKey, store: Store.settings) private var enabled = false
    @AppStorage(MouseMappings.optionKey, store: Store.settings) private var option = false
    @AppStorage(MouseMappings.minimumKey, store: Store.settings) private var minimum = 20
    @ObservedObject private var model = MouseMappings.shared
    @State private var selection: UUID?
    @State private var editor: MouseMapping?
    @State private var choosing = false
    @State private var points: [CGPoint] = []
    @State private var stroke: MouseStroke?
    @State private var confirmingRestore = false

    private var selected: MouseMapping? {
        model.mappings.first { $0.id == selection } ?? model.mappings.first
    }
    var body: some View {
        Section("Gestures") {
            SettingsSwitch("Allow Gestures", isOn: $enabled).settingsAnchor("mouse-gestures")
            SettingsSwitch("Perform Gestures with Option Key", isOn: $option)
                .disabled(!enabled).settingsAnchor("mouse-option")
        }
        Section("Gesture Mapping") {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(model.mappings) { mapping in
                        Button { selection = mapping.id } label: {
                            Text(mapping.title).frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8).padding(.vertical, 6)
                                .background(selected?.id == mapping.id ? Color.accentColor.opacity(0.15) : .clear,
                                            in: RoundedRectangle(cornerRadius: Radius.control))
                        }.buttonStyle(.plain)
                    }
                }
                Divider()
                GeometryReader { box in
                    if let selected {
                        GestureTrailPreview(points: GestureTrailPreview.example(selected.directions, in: box.size),
                                            label: selected.title, replay: true)
                    }
                }.frame(width: 176, height: 176)
            }
            HStack {
                Button("New Gesture…") {
                    choosing = true
                    editor = MouseMapping(command: "", directions: "")
                }.settingsButton()
                Button("Edit Gesture…") {
                    guard let selected else { return }
                    beginDrawing(selected)
                }.settingsButton().disabled(selected == nil)
                Button("Remove") {
                    if let selected { model.replace(model.mappings.filter { $0.id != selected.id }) }
                }.settingsButton().disabled(selected == nil)
                Spacer()
                Button("Restore Defaults") { confirmingRestore = true }.settingsButton()
            }
            .disabled(editor != nil)
            .confirmationDialog("Restore default gestures?", isPresented: $confirmingRestore) {
                Button("Restore Defaults", role: .destructive) { model.replace(MouseMappings.defaults) }
            }
        }
        if let draft = editor {
            Section(model.mappings.contains(where: { $0.id == draft.id }) ? "Edit Gesture" : "New Gesture") {
                if choosing { commandPicker(draft) } else { drawing(draft) }
            }
        }
        Section("Gesture Sensitivity") {
            SettingsRow("Minimum stroke length") {
                Slider(value: Binding(get: { Double(minimum) }, set: { minimum = Int($0.rounded()) }),
                       in: 8...64, step: 1).frame(maxWidth: 140).accessibilityLabel("Minimum stroke length")
                Text("\(minimum) pt").monospacedDigit()
            }.settingsAnchor("mouse-minimum")
        }
    }
    private static let commandOptions = Command.allCases
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        .map { DropOption(title: $0.title, value: $0.rawValue) }

    private func commandPicker(_ draft: MouseMapping) -> some View {
        HStack(spacing: 8) {
            DropMenu("Pick a command", options: Self.commandOptions,
                     selection: Binding(get: { draft.command }, set: { editor?.command = $0 }),
                     faceTitle: draft.command.isEmpty ? "Search or choose a command" : nil,
                     fillsField: true)
            Button("Next") { beginDrawing(draft) }.settingsButton().disabled(draft.command.isEmpty)
            Button("Cancel") { editor = nil }.settingsButton()
        }
    }
    private func beginDrawing(_ mapping: MouseMapping) {
        choosing = false
        points = []
        stroke = nil
        editor = MouseMapping(id: mapping.id, command: mapping.command, directions: "")
    }
    private func drawing(_ draft: MouseMapping) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(draft.title).font(.headline)
            ZStack {
                RoundedRectangle(cornerRadius: Radius.control).fill(Color.accentColor.opacity(0.06))
                RoundedRectangle(cornerRadius: Radius.control).strokeBorder(Color.accentColor.opacity(0.4))
                if points.isEmpty { Text("Draw with the primary mouse button").foregroundStyle(.secondary) }
                GestureTrailPreview(points: points,
                                    label: model.previewLabel(stroke?.directions ?? draft.directions),
                                    replay: stroke == nil && !draft.directions.isEmpty)
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(minWidth: 176, idealWidth: 224, maxWidth: 256, minHeight: 176)
            .contentShape(Rectangle()).clipped()
            .accessibilityLabel("Gesture drawing area")
            .overlay {
                MouseDrawingSurface { point in
                    points = [point]
                    stroke = MouseStroke(start: point, minimum: CGFloat(minimum))
                    editor?.directions = ""
                } move: { point in
                    points.append(point)
                    stroke?.move(to: point)
                } finish: { point in
                    stroke?.move(to: point)
                    editor?.directions = stroke?.directions ?? ""
                    stroke = nil
                }
            }
            if let conflict = model.conflict(draft) {
                Text("Already assigned to \(conflict.title). Draw another gesture.").foregroundStyle(.secondary)
            } else if !draft.directions.isEmpty { Text(MouseStroke.arrows(draft.directions)) }
            else if !points.isEmpty && stroke == nil { Text("Draw a longer stroke.").foregroundStyle(.secondary) }
            HStack {
                Button("Save Gesture") {
                    if model.save(draft) { selection = draft.id; editor = nil }
                }.settingsButton().disabled(draft.directions.isEmpty || model.conflict(draft) != nil)
                Button("Cancel") { editor = nil }.settingsButton()
            }
        }
    }
}

/// Own the complete press inside both Settings hosts, including the native form's scroll view.
private struct MouseDrawingSurface: NSViewRepresentable {
    let start: (CGPoint) -> Void
    let move: (CGPoint) -> Void
    let finish: (CGPoint) -> Void

    func makeNSView(context: Context) -> Pad { Pad(surface: self) }
    func updateNSView(_ view: Pad, context: Context) { view.surface = self }

    final class Pad: NSView {
        var surface: MouseDrawingSurface
        init(surface: MouseDrawingSurface) {
            self.surface = surface
            super.init(frame: .zero)
            setAccessibilityLabel("Gesture drawing area")
        }
        required init?(coder: NSCoder) { nil }
        override var isFlipped: Bool { true }
        override func mouseDown(with event: NSEvent) { surface.start(convert(event.locationInWindow, from: nil)) }
        override func mouseDragged(with event: NSEvent) { surface.move(convert(event.locationInWindow, from: nil)) }
        override func mouseUp(with event: NSEvent) { surface.finish(convert(event.locationInWindow, from: nil)) }
    }
}
