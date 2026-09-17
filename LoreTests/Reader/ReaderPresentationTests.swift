import CoreGraphics
import Foundation
import ReadiumShared
import Testing
import UIKit
@testable import Lore

@MainActor
private final class TestLocationProvider: ReaderLocationProviding {
    let currentLocation: Locator? = nil
    let viewController = UIViewController()
}

@MainActor
private final class TestPositionManager: ReadingPositionManaging {
    func record(_ locator: Locator) {}
    func flush(currentLocator: Locator?) async throws {}
}

@MainActor
struct ReaderPresentationTests {
    @Test func presentationCarriesCoverDataAndSourceFrame() {
        let bookID = UUID()
        let coverData = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let sourceFrame = CGRect(x: 20, y: 150, width: 100, height: 150)
        let session = ReaderSessionController(
            locationProvider: TestLocationProvider(),
            positionController: TestPositionManager()
        )

        let presentation = LibraryViewModel.ReaderPresentation(
            id: bookID,
            title: "Le Comte de Monte-Cristo",
            author: "Alexandre Dumas",
            readingStage: .inProgress,
            conversationRepository: nil,
            sourceFrame: sourceFrame,
            initialHighlight: nil,
            session: session,
            coverData: coverData
        )

        #expect(presentation.id == bookID)
        #expect(presentation.title == "Le Comte de Monte-Cristo")
        #expect(presentation.author == "Alexandre Dumas")
        #expect(presentation.sourceFrame == sourceFrame)
        #expect(presentation.coverData == coverData)
    }

    @Test func presentationAllowsNilCoverDataAndNilSourceFrame() {
        let bookID = UUID()
        let session = ReaderSessionController(
            locationProvider: TestLocationProvider(),
            positionController: TestPositionManager()
        )

        let presentation = LibraryViewModel.ReaderPresentation(
            id: bookID,
            title: "Livre sans image",
            session: session
        )

        #expect(presentation.id == bookID)
        #expect(presentation.sourceFrame == nil)
        #expect(presentation.coverData == nil)
    }

}
