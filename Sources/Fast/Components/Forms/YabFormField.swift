import SwiftUI

struct YabFormField: View {
    let title: String
    @Binding var text: String
    @FocusState private var typing: Bool

    init(_ title: String, text: Binding<String>) {
        self.title = title
        _text = text
    }

    var body: some View {
        TextField("", text: $text).textFieldStyle(.plain).focused($typing)
            .modifier(CardField(hint: title, empty: text.isEmpty, typing: typing))
            .accessibilityLabel(title)
    }
}
