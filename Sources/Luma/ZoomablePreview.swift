import SwiftUI
import AppKit

/// Native event handling keeps wheel zoom confined to the preview, including on trackpads.
struct ZoomablePreview: NSViewRepresentable {
    let itemID: UUID
    let url: URL
    let cutout: Data?
    @Binding var zoom: CGFloat

    func makeNSView(context: Context) -> PreviewCanvas { PreviewCanvas() }

    func updateNSView(_ view: PreviewCanvas, context: Context) {
        view.onZoom = { zoom = $0 }
        view.setImage(itemID: itemID, url: url, cutout: cutout)
        view.setZoom(zoom)
    }
}

struct PreviewViewport {
    static let zoomRange: ClosedRange<CGFloat> = 0.25...16
    var zoom: CGFloat = 1
    var offset = CGPoint.zero

    mutating func zoom(to value: CGFloat, anchor: CGPoint = .zero) {
        let next = min(max(value, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        let ratio = next / zoom
        offset = CGPoint(x: anchor.x - (anchor.x - offset.x) * ratio,
                         y: anchor.y - (anchor.y - offset.y) * ratio)
        zoom = next
    }

    mutating func constrain(image: CGSize, canvas: CGSize) {
        let x = max(0, (image.width * zoom - canvas.width) / 2)
        let y = max(0, (image.height * zoom - canvas.height) / 2)
        offset.x = min(max(offset.x, -x), x)
        offset.y = min(max(offset.y, -y), y)
    }
}

final class PreviewCanvas: NSView {
    var onZoom: ((CGFloat) -> Void)?
    private var image: NSImage?
    private var itemID: UUID?
    private var displayingCutout = false
    private var viewport = PreviewViewport()
    private var lastDragPoint: CGPoint?
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func setImage(itemID: UUID, url: URL, cutout: Data?) {
        guard self.itemID != itemID || displayingCutout != (cutout != nil) else { return }
        let changedItem = self.itemID != itemID
        self.itemID = itemID
        displayingCutout = cutout != nil
        // Decode the original, not the 1200px queue thumbnail, for detailed inspection.
        image = cutout.flatMap(NSImage.init(data:)) ?? NSImage(contentsOf: url)
        if changedItem { viewport = PreviewViewport() }
        needsDisplay = true
    }

    private var fittedSize: CGSize {
        guard let image, image.size.width > 0, image.size.height > 0 else { return .zero }
        let factor = min(max(1, bounds.width - 70) / image.size.width,
                         max(1, bounds.height - 70) / image.size.height)
        return CGSize(width: image.size.width * factor, height: image.size.height * factor)
    }

    func setZoom(_ zoom: CGFloat, anchor: CGPoint = .zero) {
        viewport.zoom(to: zoom, anchor: anchor)
        if zoom == 1, anchor == .zero { viewport.offset = .zero }
        viewport.constrain(image: fittedSize, canvas: bounds.size)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let image else { return }
        viewport.constrain(image: fittedSize, canvas: bounds.size)
        let size = CGSize(width: fittedSize.width * viewport.zoom, height: fittedSize.height * viewport.zoom)
        let rect = CGRect(x: bounds.midX - size.width / 2 + viewport.offset.x,
                          y: bounds.midY - size.height / 2 + viewport.offset.y,
                          width: size.width, height: size.height)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    }

    override func scrollWheel(with event: NSEvent) {
        guard event.momentumPhase.isEmpty else { return }
        let delta = event.scrollingDeltaY
        guard delta != 0 else { return }
        let point = convert(event.locationInWindow, from: nil)
        let sensitivity: CGFloat = event.hasPreciseScrollingDeltas ? 0.008 : 0.12
        let factor = exp(min(max(delta * sensitivity, -0.5), 0.5))
        setZoom(viewport.zoom * factor, anchor: CGPoint(x: point.x - bounds.midX, y: point.y - bounds.midY))
        onZoom?(viewport.zoom)
    }

    override func magnify(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        setZoom(viewport.zoom * (1 + event.magnification), anchor: CGPoint(x: point.x - bounds.midX, y: point.y - bounds.midY))
        onZoom?(viewport.zoom)
    }

    override func mouseDown(with event: NSEvent) {
        lastDragPoint = convert(event.locationInWindow, from: nil)
        NSCursor.closedHand.push()
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let last = lastDragPoint {
            viewport.offset.x += point.x - last.x
            viewport.offset.y += point.y - last.y
            viewport.constrain(image: fittedSize, canvas: bounds.size)
            needsDisplay = true
        }
        lastDragPoint = point
    }

    override func mouseUp(with event: NSEvent) {
        if lastDragPoint != nil { NSCursor.pop() }
        lastDragPoint = nil
    }
}
