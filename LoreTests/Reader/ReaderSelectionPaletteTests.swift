import Testing
@testable import Lore

struct ReaderSelectionPaletteTests {
    @Test func selectionUsesDedicatedHighContrastColors() {
        #expect(ReaderSelectionPalette.background == "#66E3FF")
        #expect(ReaderSelectionPalette.text == "#071018")
        #expect(ReaderSelectionPalette.background != "#FFD54F")
    }
}
