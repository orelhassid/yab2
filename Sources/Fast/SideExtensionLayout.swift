import Foundation

/// Pinned extensions share the address until they need their own row.
/// The row keeps its room while the pointer is outside the sidebar.
struct SideExtensionLayout {
    let separate: Bool
    let columns: Int
    let cell: CGFloat
    let height: CGFloat
    let gap: CGFloat

    init(width: CGFloat, count: Int, door: CGFloat, controls: Int, margin: CGFloat, columns: Int, gap: CGFloat) {
        self.gap = gap
        let available = max(door, width - 2 * margin)
        let inline = max(0, Int((available - 96 - door * CGFloat(controls)) / (door + 2)))
        separate = count > inline && count > 0
        self.columns = max(1, columns)
        cell = (available - CGFloat(self.columns - 1) * gap) / CGFloat(self.columns)
        let rows = count > 0 ? (count + self.columns - 1) / self.columns : 0
        height = separate ? CGFloat(rows) * (door + gap) : 0
    }
}
