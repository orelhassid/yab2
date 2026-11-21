import SwiftUI

struct YabValueBadge: View {
    let title: String
    let tint: FolderTint
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(title).font(.caption).lineLimit(1)
            .foregroundStyle(tint.ink(dark: scheme == .dark))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(tint.wash(dark: scheme == .dark), in: Capsule())
    }
}
