import XCTest
@testable import Luma

final class PreviewViewportTests: XCTestCase {
    func testZoomKeepsPointUnderCursorFixed() {
        var viewport = PreviewViewport()
        viewport.offset = CGPoint(x: 20, y: -10)
        let anchor = CGPoint(x: 80, y: 30)
        let originalX = (anchor.x - viewport.offset.x) / viewport.zoom
        let originalY = (anchor.y - viewport.offset.y) / viewport.zoom
        viewport.zoom(to: 3, anchor: anchor)
        XCTAssertEqual((anchor.x - viewport.offset.x) / viewport.zoom, originalX, accuracy: 0.001)
        XCTAssertEqual((anchor.y - viewport.offset.y) / viewport.zoom, originalY, accuracy: 0.001)
    }

    func testZoomLimitsAndPanBounds() {
        var viewport = PreviewViewport()
        viewport.zoom(to: 100)
        XCTAssertEqual(viewport.zoom, 16)
        viewport.zoom(to: 0.01)
        XCTAssertEqual(viewport.zoom, 0.25)
        viewport.zoom(to: 2)
        viewport.offset = CGPoint(x: 999, y: -999)
        viewport.constrain(image: CGSize(width: 300, height: 200), canvas: CGSize(width: 400, height: 300))
        XCTAssertEqual(viewport.offset, CGPoint(x: 100, y: -50))
        viewport.zoom(to: 0.5)
        viewport.constrain(image: CGSize(width: 300, height: 200), canvas: CGSize(width: 400, height: 300))
        XCTAssertEqual(viewport.offset, .zero)
    }
}
