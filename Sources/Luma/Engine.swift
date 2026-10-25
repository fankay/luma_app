import AppKit
import ImageIO
import UniformTypeIdentifiers
import Vision
import CoreImage

enum OutputFormat: String, CaseIterable, Identifiable {
    case heic = "HEIC", jpeg = "JPEG", png = "PNG", tiff = "TIFF"
    var id: String { rawValue }
    var type: UTType { switch self { case .heic: .heic; case .jpeg: .jpeg; case .png: .png; case .tiff: .tiff } }
    var ext: String { self == .jpeg ? "jpg" : rawValue.lowercased() }
}
enum ProcessingMode: String, CaseIterable, Identifiable {
    case quality = "高质量压缩", lossless = "严格无损", removeBackground = "移除背景"
    var id: String { rawValue }
}
struct ImageResult { let url: URL; let originalBytes: Int; let outputBytes: Int; let note: String }
enum ImageFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
struct ImageEngine {
    static func size(_ url: URL) -> Int { (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }
    static func process(url: URL, folder: URL, format: OutputFormat, mode: ProcessingMode, quality: Double, preparedCutout: Data? = nil) throws -> ImageResult {
        if mode == .removeBackground {
            let output = try preparedCutout ?? removeBackground(url: url)
            return try save(output, source: url, folder: folder, ext: "png", suffix: "-nobg", note: "背景已移除 · 透明 PNG")
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil), let sourceType = CGImageSourceGetType(source) else { throw ImageFailure.message("无法读取这张图片，文件可能已损坏。") }
        guard CGImageSourceGetCount(source) == 1 else { throw ImageFailure.message("暂不处理动画或多页图片，以免丢失帧或页面。") }
        let original = try Data(contentsOf: url)
        let type = mode == .lossless ? sourceType : format.type.identifier as CFString
        let ext = mode == .lossless ? url.pathExtension : format.ext
        let supported = CGImageDestinationCopyTypeIdentifiers() as! [String]
        guard supported.contains(type as String) else { throw ImageFailure.message("这台 Mac 不支持该格式的编码。") }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type, 1, nil) else { throw ImageFailure.message("无法创建图片编码器。") }
        var properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]) ?? [:]
        if mode == .quality {
            properties[kCGImageDestinationLossyCompressionQuality as String] = quality
            if format == .jpeg, [.first, .last, .premultipliedFirst, .premultipliedLast].contains(image.alphaInfo) { throw ImageFailure.message("图片含透明通道。请选择 PNG 或 HEIC，避免转换 JPEG 时丢失透明背景。") }
        } else {
            properties[kCGImageDestinationLossyCompressionQuality as String] = 1.0
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ImageFailure.message("编码失败，请尝试其他格式。") }
        var output = data as Data
        var note = "已完成"
        if mode == .lossless {
            // Conservative: retain original if exact decoded pixels cannot be established.
            let candidateSource = CGImageSourceCreateWithData(output as CFData, nil)
            let candidate = candidateSource.flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
            if output.count >= original.count || candidate.map({ !pixelsEqual(image, $0) }) != false {
                output = original
                note = "已是最佳无损体积 · 保留原文件"
            } else { note = "像素校验通过 · 无损优化" }
        }
        return try save(output, source: url, folder: folder, ext: ext, suffix: "-luma", note: note)
    }

    /// Vision receives upright pixels, so rotated HEIC/JPEG files and their masks stay aligned.
    static func removeBackground(url: URL) throws -> Data {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) == 1,
              let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else {
            throw ImageFailure.message("无法移除背景：请选择单张静态图片，动画和多页图片暂不支持。")
        }
        let context = CIContext()
        let upright = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        guard let pixels = context.createCGImage(upright, from: upright.extent) else {
            throw ImageFailure.message("无法读取图片像素，请尝试其他图片。")
        }
        let handler = VNImageRequestHandler(cgImage: pixels, options: [:])
        let request = VNGenerateForegroundInstanceMaskRequest()
        do { try handler.perform([request]) }
        catch { throw ImageFailure.message("主体识别失败，请重试或更换图片。系统提示：\(error.localizedDescription)") }
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
            throw ImageFailure.message("未识别到清晰主体，请选择人物、宠物或商品更突出的图片。")
        }
        // Keep all foreground subjects and the original canvas, including soft alpha edges.
        let buffer = try observation.generateMaskedImage(ofInstances: observation.allInstances, from: handler, croppedToInstancesExtent: false)
        return try transparentPNG(CIImage(cvPixelBuffer: buffer), context: context)
    }

    static func transparentPNG(_ image: CIImage, context: CIContext = CIContext()) throws -> Data {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let data = context.pngRepresentation(of: image, format: .RGBA8, colorSpace: colorSpace) else {
            throw ImageFailure.message("无法生成透明 PNG，请重试。")
        }
        return data
    }

    static func save(_ output: Data, source url: URL, folder: URL, ext: String, suffix: String, note: String) throws -> ImageResult {
        let base = url.deletingPathExtension().lastPathComponent + suffix
        var target = folder.appendingPathComponent(base).appendingPathExtension(ext)
        var index = 2
        while FileManager.default.fileExists(atPath: target.path) { target = folder.appendingPathComponent("\(base)-\(index)").appendingPathExtension(ext); index += 1 }
        try output.write(to: target, options: .withoutOverwriting)
        return ImageResult(url: target, originalBytes: size(url), outputBytes: output.count, note: note)
    }
    static func pixelsEqual(_ a: CGImage, _ b: CGImage) -> Bool {
        guard a.width == b.width, a.height == b.height, a.bitsPerComponent == b.bitsPerComponent, a.bitsPerPixel == b.bitsPerPixel, a.bytesPerRow == b.bytesPerRow, a.alphaInfo == b.alphaInfo, a.bitmapInfo == b.bitmapInfo, a.colorSpace == b.colorSpace,
              let ad = a.dataProvider?.data, let bd = b.dataProvider?.data else { return false }
        return (ad as Data) == (bd as Data)
    }
}
