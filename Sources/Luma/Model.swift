import SwiftUI
import UniformTypeIdentifiers

struct ImageItem: Identifiable {
    let id = UUID()
    let url: URL
    let thumbnail: NSImage?
    let bytes: Int
    let dimensions: String
    var result: ImageResult?
    var error: String?
    var working = false
}
@MainActor final class Workspace: ObservableObject {
    @Published var items: [ImageItem] = []
    @Published var selected: UUID?
    @Published var format: OutputFormat = .heic
    @Published var mode: ProcessingMode = .quality
    @Published var quality = 0.88
    @Published var running = false
    @Published var completed = 0
    @Published var alert: String?
    @Published var outputFolder: URL?
    var current: ImageItem? { items.first { $0.id == selected } ?? items.first }
    var saved: Int { items.compactMap(\.result).reduce(0) { $0 + $1.originalBytes - $1.outputBytes } }
    func chooseImages() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]; panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        if panel.runModal() == .OK { add(panel.urls) }
    }
    func add(_ urls: [URL]) {
        guard !running else { return }
        for url in urls where !items.contains(where: { $0.url == url }) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { alert = "无法读取 \(url.lastPathComponent)"; continue }
            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
            let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1200, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary)
            items.append(ImageItem(url: url, thumbnail: thumb.map { NSImage(cgImage: $0, size: .zero) }, bytes: ImageEngine.size(url), dimensions: "\(props?[kCGImagePropertyPixelWidth as String] as? Int ?? 0) × \(props?[kCGImagePropertyPixelHeight as String] as? Int ?? 0)"))
        }
        if selected == nil { selected = items.first?.id }
    }
    func export() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true; panel.prompt = "导出到这里"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        outputFolder = folder; running = true; completed = 0
        let chosenFormat = format, chosenMode = mode, chosenQuality = quality
        Task {
            for index in items.indices {
                items[index].working = true; items[index].error = nil; items[index].result = nil
                let url = items[index].url
                do {
                    let result = try await Task.detached(priority: .userInitiated) { try ImageEngine.process(url: url, folder: folder, format: chosenFormat, mode: chosenMode, quality: chosenQuality) }.value
                    items[index].result = result
                } catch { items[index].error = error.localizedDescription }
                items[index].working = false; completed += 1
            }
            running = false
        }
    }
    static func bytes(_ value: Int) -> String { ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file) }
}
