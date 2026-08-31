import Foundation
import Testing
@testable import Lore

struct ReaderSelectionPaletteTests {
    @Test func selectionUsesDedicatedHighContrastColors() {
        #expect(ReaderSelectionPalette.background == "#8EEBFF")
        #expect(ReaderSelectionPalette.text == "#001319")
        #expect(ReaderSelectionPalette.background != "#FFD54F")
    }

    @Test func webViewScriptReinforcesSelectionInsteadOfOnlyDefiningUnusedTokens() {
        let script = ReaderSelectionPalette.webViewStyleScript(verticalMargins: 1.5)
        #expect(script.contains("*::selection"))
        #expect(script.contains("!important"))
        #expect(script.contains(ReaderSelectionPalette.background))
        #expect(script.contains(ReaderSelectionPalette.text))
        #expect(script.contains("padding-block-start: 1.5rem"))
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
