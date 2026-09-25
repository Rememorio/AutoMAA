import Testing
@testable import AutoMAA

@Suite("Delimited list editing")
struct DelimitedListFieldTests {
    @Test("typed separators remain in the draft while parsed values stay current")
    func preservesSeparatorsDuringTyping() {
        var draft = DelimitedListDraft(values: [])
        for character in "abc,def" {
            draft.update(draft.text + String(character))
            if character == "," {
                #expect(draft.text == "abc,")
                #expect(draft.values == ["abc"])
            }
        }
        #expect(draft.text == "abc,def")
        #expect(draft.values == ["abc", "def"])
        draft.finishEditing()
        #expect(draft.text == "abc、def")
    }

    @Test("navigation can use current values without waiting for editing to finish")
    func retainsValuesBeforeFocusLoss() {
        var draft = DelimitedListDraft(values: ["旧项目"])
        draft.update(" 招聘许可，龙门币; 家具零件； ")
        #expect(draft.text == " 招聘许可，龙门币; 家具零件； ")
        #expect(draft.values == ["招聘许可", "龙门币", "家具零件"])
        let reopened = DelimitedListDraft(values: draft.values)
        #expect(reopened.text == "招聘许可、龙门币、家具零件")
    }

    @Test("clearing and incomplete trailing items never create empty list entries")
    func handlesEmptyInput() {
        var draft = DelimitedListDraft(values: ["支援机械"])
        draft.update(" ，、;； ")
        #expect(draft.values.isEmpty)
        draft.finishEditing()
        #expect(draft.text.isEmpty)
    }
}
