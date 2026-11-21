import SwiftUI

struct FormChoiceCard: View {
    let title: String
    let detail: String
    let icon: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false
    @FocusState private var focused: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.surface)
        let accent = Color.accentColor
        Button(action: action) {
            HStack(spacing: CardFrame.inset) {
                Symbol(icon, size: 17)
                    .foregroundStyle(selected ? accent : Palette.muted)
                    .frame(width: 34, height: 34)
                    .background(selected ? accent.opacity(0.14) : Palette.ink.opacity(0.05),
                                in: RoundedRectangle(cornerRadius: Radius.control))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(detail).font(.caption).foregroundStyle(Palette.muted).lineLimit(1)
                }
                Spacer(minLength: 0)
                if selected { Symbol("checkmark.circle.fill", size: 14).foregroundStyle(accent) }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(selected ? accent.opacity(hovering ? 0.14 : 0.08) : Palette.ink.opacity(hovering ? 0.085 : 0.025)))
            .overlay(shape.strokeBorder(selected ? accent : Palette.ink.opacity(hovering ? 0.35 : 0.14), lineWidth: 1))
            .overlay { if focused { shape.inset(by: -2).stroke(accent, lineWidth: 2) } }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .focusable().focused($focused).focusEffectDisabled()
        .onHover { hovering = $0 }
        .accessibilityLabel(title)
        .accessibilityHint(detail)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
