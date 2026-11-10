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
    case quality = "高质量压缩", lossless = "严格无损", removeBackground = "移除背景", removeWatermark = "去除水印"
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
        let result = try render(url: url, format: format, mode: mode, quality: quality, preparedCutout: preparedCutout)
        return try save(result.data, source: url, folder: folder, ext: result.ext, suffix: result.suffix, note: result.note)
    }

    /// Shared by file export and clipboard so both use the current processing settings.
    static func render(url: URL, format: OutputFormat, mode: ProcessingMode, quality: Double, preparedCutout: Data? = nil) throws -> (data: Data, ext: String, suffix: String, note: String) {
        if mode == .removeWatermark {
            guard let data = preparedCutout else { throw ImageFailure.message("请先完成水印识别。") }
            return (data, "png", "-clean", "水印处理完成 · PNG")
        }
        if mode == .removeBackground {
            let output = try preparedCutout ?? removeBackground(url: url)
            return (output, "png", "-nobg", "背景已移除 · 透明 PNG")
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
        return (output, ext, "-luma", note)
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
        if let flat = removeFlatBackground(pixels) {
            return try transparentPNG(CIImage(cgImage: flat), context: context)
        }
        let handler = VNImageRequestHandler(cgImage: pixels, options: [:])
        let request = VNGenerateForegroundInstanceMaskRequest()
        do { try handler.perform([request]) }
        catch { throw ImageFailure.message("主体识别失败，请重试或更换图片。系统提示：\(error.localizedDescription)") }
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
            throw ImageFailure.message("未能识别主体或纯色背景，请尝试其他图片。")
        }
        // Keep all foreground subjects and the original canvas, including soft alpha edges.
        let buffer = try observation.generateMaskedImage(ofInstances: observation.allInstances, from: handler, croppedToInstancesExtent: false)
        return try transparentPNG(CIImage(cvPixelBuffer: buffer), context: context)
    }

    /// Detect a uniform border before using Vision, which is intended for photographic subjects.
    static func removeFlatBackground(_ image: CGImage) -> CGImage? {
        let width = image.width, height = image.height
        guard width > 1, height > 1, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        return bytes.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            let p = raw.bindMemory(to: UInt8.self)
            var counts: [UInt32: Int] = [:]
            for i in 0..<(2 * width + 2 * height) {
                let x: Int, y: Int
                if i < width { x = i; y = 0 }
                else if i < 2 * width { x = i - width; y = height - 1 }
                else if i < 2 * width + height { x = 0; y = i - 2 * width }
                else { x = width - 1; y = i - 2 * width - height }
                let n = (y * width + x) * 4
                guard p[n + 3] == 255 else { continue }
                let key = UInt32(p[n]) << 16 | UInt32(p[n + 1]) << 8 | UInt32(p[n + 2])
                counts[key, default: 0] += 1
            }
            guard let dominant = counts.max(by: { $0.value < $1.value }), dominant.value * 100 >= (2 * width + 2 * height) * 90 else { return nil }
            let bg = [Int((dominant.key >> 16) & 255), Int((dominant.key >> 8) & 255), Int(dominant.key & 255)]
            for n in stride(from: 0, to: p.count, by: 4) {
                let oldAlpha = Int(p[n + 3])
                guard oldAlpha == 255 else { continue }
                let distance = (0..<3).map { abs(Int(p[n + $0]) - bg[$0]) }.max() ?? 0
                if distance == 0 { p[n + 3] = 0; p[n] = 0; p[n + 1] = 0; p[n + 2] = 0 }
                else if distance < 32 {
                    // Recover the edge color blended against the detected background.
                    let alpha = distance * 255 / 32
                    for c in 0..<3 { p[n + c] = UInt8(max(0, min(255, Int(p[n + c]) - bg[c] * (255 - alpha) / 255))) }
                    p[n + 3] = UInt8(alpha)
                }
            }
            return ctx.makeImage()
        }
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
