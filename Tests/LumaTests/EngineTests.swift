import XCTest
import AppKit
import ImageIO
import CoreImage
@testable import Luma

final class EngineTests: XCTestCase {
    func testTransparentPNGExportPreservesAlphaAndDoesNotOverwrite() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = CIImage(color: CIColor(red: 1, green: 0, blue: 0, alpha: 0.5)).cropped(to: CGRect(x: 0, y: 0, width: 16, height: 12))
        let png = try ImageEngine.transparentPNG(image)
        let source = folder.appendingPathComponent("original.png")
        try png.write(to: source)
        let result = try ImageEngine.process(url: source, folder: folder, format: .jpeg, mode: .removeBackground, quality: 0.5, preparedCutout: png)
        XCTAssertEqual(result.url.lastPathComponent, "original-nobg.png")
        let repeated = try ImageEngine.process(url: source, folder: folder, format: .heic, mode: .removeBackground, quality: 1, preparedCutout: png)
        XCTAssertNotEqual(result.url, repeated.url)
        let decodedSource = try XCTUnwrap(CGImageSourceCreateWithURL(result.url as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetType(decodedSource) as String?, "public.png")
        let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(decodedSource, 0, nil))
        XCTAssertEqual(decoded.width, 16)
        XCTAssertEqual(decoded.height, 12)
        let alpha = try alphaValues(decoded)
        XCTAssertTrue(alpha.allSatisfy { (126...129).contains(Int($0)) }, "PNG must retain soft, semitransparent edges")
        XCTAssertEqual(try Data(contentsOf: source), png)
    }

    func testBackgroundRemovalRejectsInvalidImage() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        try Data("not an image".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try ImageEngine.removeBackground(url: url))
    }

    func testBackgroundRemovalRejectsMultipageImages() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".tiff")
        defer { try? FileManager.default.removeItem(at: url) }
        let context = try XCTUnwrap(CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.tiff" as CFString, 2, nil))
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        XCTAssertThrowsError(try ImageEngine.removeBackground(url: url))
    }

    /// Run with a supplied public test photograph to exercise the actual on-device model.
    func testVisionIntegrationWhenFixtureProvided() throws {
        guard let path = ProcessInfo.processInfo.environment["LUMA_SEGMENTATION_TEST_IMAGE"] else {
            throw XCTSkip("Set LUMA_SEGMENTATION_TEST_IMAGE to run the on-device Vision integration test")
        }
        let originalURL = URL(fileURLWithPath: path)
        let originalData = try Data(contentsOf: originalURL)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let result = try ImageEngine.process(url: originalURL, folder: folder, format: .jpeg, mode: .removeBackground, quality: 0.5)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(result.url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let input = try XCTUnwrap(CIImage(contentsOf: originalURL, options: [.applyOrientationProperty: true]))
        XCTAssertEqual(image.width, Int(input.extent.width))
        XCTAssertEqual(image.height, Int(input.extent.height))
        let alpha = try alphaValues(image)
        XCTAssertTrue(alpha.contains { $0 == 0 }, "Background should become fully transparent")
        XCTAssertTrue(alpha.contains { $0 > 240 }, "Subject should remain opaque")
        XCTAssertTrue(alpha.contains { $0 > 0 && $0 < 255 }, "Subject edges should retain soft alpha")
        XCTAssertEqual(try Data(contentsOf: originalURL), originalData)

        let rotatedURL = folder.appendingPathComponent("rotated.jpg")
        let originalSource = try XCTUnwrap(CGImageSourceCreateWithURL(originalURL as CFURL, nil))
        let rawPixels = try XCTUnwrap(CGImageSourceCreateImageAtIndex(originalSource, 0, nil))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(rotatedURL as CFURL, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, rawPixels, [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let rotatedPNG = try ImageEngine.removeBackground(url: rotatedURL)
        let rotatedSource = try XCTUnwrap(CGImageSourceCreateWithData(rotatedPNG as CFData, nil))
        let rotated = try XCTUnwrap(CGImageSourceCreateImageAtIndex(rotatedSource, 0, nil))
        XCTAssertEqual(rotated.width, rawPixels.height)
        XCTAssertEqual(rotated.height, rawPixels.width)
    }

    private func alphaValues(_ image: CGImage) throws -> [UInt8] {
        let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        return stride(from: 3, to: image.width * image.height * 4, by: 4).map { pixels[$0] }
    }

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
