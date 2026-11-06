import AppKit
import CoreImage

enum ClipboardImage {
    /// PNG and TIFF provide actual image pixels to receiving apps, including alpha.
    /// Normalize EXIF orientation before putting the image on the pasteboard.
    static func representations(from data: Data) throws -> (png: Data, tiff: Data) {
        guard let image = CIImage(data: data, options: [.applyOrientationProperty: true]) else {
            throw ImageFailure.message("无法读取处理后的图片。")
        }
        let png = try ImageEngine.transparentPNG(image)
        guard let tiff = NSBitmapImageRep(data: png)?.tiffRepresentation else {
            throw ImageFailure.message("无法准备剪贴板图片，请重试。")
        }
        return (png, tiff)
    }

    @MainActor static func write(_ representations: (png: Data, tiff: Data), to pasteboard: NSPasteboard = .general) throws {
        let item = NSPasteboardItem()
        guard item.setData(representations.png, forType: .png),
              item.setData(representations.tiff, forType: .tiff) else {
            throw ImageFailure.message("无法准备剪贴板数据。")
        }
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else {
            throw ImageFailure.message("复制失败，剪贴板可能正被其他应用使用，请重试。")
        }
    }
}
