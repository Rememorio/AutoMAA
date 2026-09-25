import Foundation
import SwiftUI

struct DelimitedListDraft {
    private(set) var text: String

    init(values: [String]) {
        text = values.joined(separator: "、")
    }

    var values: [String] {
        text.components(separatedBy: CharacterSet(charactersIn: "、,，;；"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    mutating func update(_ text: String) {
        self.text = text
    }

    mutating func finishEditing() {
        text = values.joined(separator: "、")
    }
}

struct DelimitedListField: View {
    let title: String
    let prompt: String
    @Binding private var values: [String]
    @State private var draft: DelimitedListDraft
    @FocusState private var isFocused: Bool

    init(_ title: String, prompt: String, values: Binding<[String]>) {
        self.title = title
        self.prompt = prompt
        _values = values
        _draft = State(initialValue: DelimitedListDraft(values: values.wrappedValue))
    }

    var body: some View {
        TextField(title, text: Binding(
            get: { draft.text },
            set: { text in
                draft.update(text)
                values = draft.values
            }
        ), prompt: Text(prompt))
        .textFieldStyle(.roundedBorder)
        .focused($isFocused)
        .accessibilityLabel(title)
        .accessibilityHint("多项用顿号、逗号或分号分隔")
        .onSubmit { draft.finishEditing() }
        .onChange(of: isFocused) { _, focused in
            if !focused { draft.finishEditing() }
        }
        .onChange(of: values) { _, updated in
            if !isFocused { draft = DelimitedListDraft(values: updated) }
        }
    }
}
