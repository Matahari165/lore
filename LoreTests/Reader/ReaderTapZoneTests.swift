import Testing
@testable import Lore

struct ReaderTapZoneTests {
    @Test func leftToRightZonesUsePhysicalOuterThirds() {
        #expect(ReaderTapZone.resolve(x: 10, width: 390, isRTL: false) == .backward)
        #expect(ReaderTapZone.resolve(x: 195, width: 390, isRTL: false) == .chrome)
        #expect(ReaderTapZone.resolve(x: 380, width: 390, isRTL: false) == .forward)
    }

    @Test func rightToLeftZonesAreReversed() {
        #expect(ReaderTapZone.resolve(x: 10, width: 390, isRTL: true) == .forward)
        #expect(ReaderTapZone.resolve(x: 380, width: 390, isRTL: true) == .backward)
    }

    @Test func invalidWidthFallsBackToChrome() {
        #expect(ReaderTapZone.resolve(x: 0, width: 0, isRTL: false) == .chrome)
    }
}
