import XCTest
import AppKit
import CoreImage
import ImageIO
@testable import Luma

final class ClipboardImageTests: XCTestCase {
    @MainActor func testClipboardContainsPixelsWithTransparency() throws {
        let image = CIImage(color: CIColor(red: 0.3, green: 0.6, blue: 0.9, alpha: 0.5))
            .cropped(to: CGRect(x: 0, y: 0, width: 24, height: 16))
        let png = try ImageEngine.transparentPNG(image)
        let data = try ClipboardImage.representations(from: png)
        // A private pasteboard keeps tests from replacing the user's clipboard.
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        try ClipboardImage.write(data, to: board)
        XCTAssertEqual(board.pasteboardItems?.count, 1)
        XCTAssertEqual(board.data(forType: .png), data.png)
        XCTAssertEqual(board.data(forType: .tiff), data.tiff)
        XCTAssertNil(board.data(forType: .fileURL), "Copy actual pixels, not a file path")
        for representation in [data.png, data.tiff] {
            let source = try XCTUnwrap(CGImageSourceCreateWithData(representation as CFData, nil))
            let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            XCTAssertEqual(decoded.width, 24)
            XCTAssertEqual(decoded.height, 16)
            let alpha = try XCTUnwrap(CGContext(data: nil, width: 24, height: 16, bitsPerComponent: 8, bytesPerRow: 96, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            alpha.draw(decoded, in: CGRect(x: 0, y: 0, width: 24, height: 16))
            let bytes = try XCTUnwrap(alpha.data).assumingMemoryBound(to: UInt8.self)
            XCTAssertTrue((126...129).contains(Int(bytes[3])))
        }
    }

    func testRenderUsesCurrentModeWithoutExportingAFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        let original = try ImageEngine.transparentPNG(CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 40, height: 20)))
        let cutout = try ImageEngine.transparentPNG(CIImage(color: .clear).cropped(to: CGRect(x: 0, y: 0, width: 40, height: 20)))
        try original.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let backgroundRemoved = try ImageEngine.render(url: url, format: .jpeg, mode: .removeBackground, quality: 0.88, preparedCutout: cutout)
        XCTAssertEqual(backgroundRemoved.data, cutout)
        let lossless = try ImageEngine.render(url: url, format: .heic, mode: .lossless, quality: 0.5, preparedCutout: cutout)
        XCTAssertNotEqual(lossless.data, cutout, "Switching modes must not copy a stale cutout")
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testRejectsInvalidClipboardImage() {
        XCTAssertThrowsError(try ClipboardImage.representations(from: Data("invalid".utf8)))
    }
}
