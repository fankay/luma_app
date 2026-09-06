import XCTest
import AppKit
import ImageIO
@testable import Luma

final class EngineTests: XCTestCase {
    func testEncodingAndLossless() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let context = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.3, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        let source = folder.appendingPathComponent("source.png")
        let dest = CGImageDestinationCreateWithURL(source as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, context.makeImage()!, nil); XCTAssertTrue(CGImageDestinationFinalize(dest))
        let original = try Data(contentsOf: source)
        for format in OutputFormat.allCases {
            let result = try ImageEngine.process(url: source, folder: folder, format: format, mode: .quality, quality: 0.88)
            let decoded = CGImageSourceCreateWithURL(result.url as CFURL, nil)!
            XCTAssertEqual(CGImageSourceGetType(decoded) as String?, format.type.identifier)
            XCTAssertEqual(CGImageSourceCreateImageAtIndex(decoded, 0, nil)?.width, 64)
        }
        let lossless = try ImageEngine.process(url: source, folder: folder, format: .heic, mode: .lossless, quality: 0.5)
        XCTAssertLessThanOrEqual(lossless.outputBytes, original.count)
        XCTAssertEqual(lossless.url.pathExtension, "png")
        let repeatResult = try ImageEngine.process(url: source, folder: folder, format: .heic, mode: .lossless, quality: 0.5)
        XCTAssertNotEqual(lossless.url, repeatResult.url)
        XCTAssertEqual(try Data(contentsOf: source), original)
    }
}
