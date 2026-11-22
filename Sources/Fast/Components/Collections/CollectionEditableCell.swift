import SwiftUI

struct CollectionCellPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(configuration.isPressed ? Palette.hairline : .clear)
    }
}

struct CollectionEditableCell<Content: View>: View {
    let property: CollectionProperty
    let entry: CollectionEntry
    let primary: Bool
    let height: CGFloat
    let collection: PageCollection
    let save: (String) -> Void
    let open: () -> Void
    @ViewBuilder let content: () -> Content
    @Environment(\.tone) private var tone
    @State private var hovering = false
    @State private var editing = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    private var original: String { entry.values[property.id] ?? "" }
    private var normalized: String? {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return property.required ? nil : "" }
        if property.numeric {
            return (try? Decimal(trimmed, format: .number)).map { NSDecimalNumber(decimal: $0).stringValue }
        }
        return draft
    }

    var body: some View {
        HStack(spacing: 0) {
            Button {
                draft = original
                editing = true
            } label: {
                content().font(CardFrame.detail).lineLimit(1)
                    .padding(.horizontal, DropFace.inset)
                    .frame(maxWidth: .infinity, minHeight: height, alignment: property.numeric ? .trailing : .leading)
                    .clipped().contentShape(Rectangle())
            }.buttonStyle(CollectionCellPress()).focused($focused)
                .accessibilityLabel("Edit " + property.title).accessibilityValue(original.isEmpty ? "Empty" : original)
                .popover(isPresented: $editing) {
                    VStack(alignment: .leading, spacing: 8) {
                        if property.type == .select || property.type == .multiSelect {
                            RecordOptionField(property: property, options: collection.options(for: property), value: $draft)
                        } else {
                            YabFormField(property.title, text: $draft).onSubmit(commit)
                        }
                        if normalized == nil {
                            Text(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "A value is required." : "Enter a number.")
                                .font(.caption).foregroundStyle(.red)
                        }
                        HStack {
                            Spacer()
                            Button("Cancel") { editing = false }.buttonStyle(.yab(.quiet, .small)).keyboardShortcut(.cancelAction)
                            Button("Save", action: commit).buttonStyle(.yab(.primary, .small)).keyboardShortcut(.defaultAction)
                                .disabled(normalized == nil)
                        }
                    }.padding(10).frame(width: 240).toned(tone)
                }
            if primary && (hovering || focused) {
                Button(action: open) { Symbol("arrow.up.right", size: 12) }
                    .buttonStyle(.yab(.quiet, .small)).accessibilityLabel("Open " + original)
            }
        }.background(hovering || editing ? Palette.hairline.opacity(0.6) : .clear)
        .overlay { if editing || focused { Rectangle().strokeBorder(Color.accentColor, lineWidth: 1).allowsHitTesting(false) } }
        .contentShape(Rectangle()).onHover { hovering = $0 }
        .accessibilityAction(named: "Edit value") { draft = original; editing = true }
        .accessibilityActions { if primary { Button("Open record", action: open) } }
        .onKeyPress(.return, phases: .down) { press in
            guard primary, press.modifiers.contains(.command) else { return .ignored }
            open()
            return .handled
        }
    }

    private func commit() {
        guard let normalized else { return }
        editing = false
        save(normalized)
    }
}
