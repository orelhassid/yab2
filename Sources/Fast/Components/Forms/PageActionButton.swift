import SwiftUI
import YabDesign

/// A page action uses Yab's button metrics and focus behavior with a quiet,
/// outlined secondary face on the collection canvas.
struct PageActionButton: View {
    enum State: Equatable { case ready, active, disabled, loading, error(String) }
    let title: String
    var icon: String?
    var variant: ButtonKind = .secondary
    var size: ButtonSize = .small
    var state: State = .ready
    var iconOnly = false
    var capsule = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if state == .loading {
                    ProgressView().controlSize(.small)
                } else if let icon {
                    Symbol(icon, size: size.wordSize)
                }
                if !iconOnly { Text(title) }
            }
        }
        .buttonStyle(.yab(variant == .secondary && state != .active ? .quiet : variant,
                          size, tint: tint, icon: iconOnly ? .square : nil, capsule: capsule))
        .background {
            if variant == .secondary {
                RoundedRectangle(cornerRadius: capsule ? size.height / 2 : Radius.control).fill(Palette.hairline.opacity(state == .active ? 0.65 : 0.2))
            }
        }
        .disabled(state == .disabled || state == .loading)
        .accessibilityLabel(title)
        .accessibilityValue(statusText)
        .accessibilityAddTraits(state == .active ? .isSelected : [])
        .keyTip(title)
    }

    private var tint: Color? {
        if case .error = state { return .red }
        return nil
    }

    private var statusText: String {
        switch state {
        case .loading: "Loading"
        case let .error(message): message
        default: ""
        }
    }
}
