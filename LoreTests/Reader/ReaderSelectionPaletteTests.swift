import Foundation
import Testing
@testable import Lore

struct ReaderSelectionPaletteTests {
    @Test func selectionUsesDedicatedHighContrastColors() {
        #expect(ReaderSelectionPalette.background == "#00E5FF")
        #expect(ReaderSelectionPalette.text == "#001018")
        #expect(ReaderSelectionPalette.background != "#FFD54F")
    }

    @Test func webViewScriptReinforcesSelectionInsteadOfOnlyDefiningUnusedTokens() {
        #expect(ReaderSelectionPalette.webViewStyleScript.contains("*::selection"))
        #expect(ReaderSelectionPalette.webViewStyleScript.contains("!important"))
        #expect(ReaderSelectionPalette.webViewStyleScript.contains(ReaderSelectionPalette.background))
        #expect(ReaderSelectionPalette.webViewStyleScript.contains(ReaderSelectionPalette.text))
    }

    @Test func markdownRendererRemovesFormattingMarkersFromDisplayedText() {
        let rendered = ReaderMarkdownRenderer.attributedString(
            from: "# Idée\n\nVoici **le point essentiel** et *un détail*.\n\n- Premier point"
        )

        #expect(rendered != nil)
        #expect(!String(rendered!.characters).contains("**"))
        #expect(!String(rendered!.characters).contains("*un détail*"))
        #expect(String(rendered!.characters).contains("le point essentiel"))
        #expect(String(rendered!.characters).contains("Premier point"))
    }
}
