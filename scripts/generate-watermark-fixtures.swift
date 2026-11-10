import AppKit

// Deterministic synthetic fixtures with clean references for evaluating restoration.
let folder = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Tests/Fixtures/Watermarks", isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
let size = NSSize(width: 640, height: 400)
func save(_ image: NSImage, _ name: String) throws {
    guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { fatalError("PNG encoding failed") }
    try png.write(to: folder.appendingPathComponent(name))
}
for kind in 0..<3 {
    let clean = NSImage(size: size, flipped: false) { rect in
        NSColor(calibratedRed: 0.15, green: 0.29, blue: 0.35, alpha: 1).setFill(); rect.fill()
        if kind == 0 {
            NSGradient(starting: .systemTeal, ending: .systemIndigo)?.draw(in: rect, angle: 25)
        } else if kind == 1 {
            for x in 0..<32 { for y in 0..<20 {
                NSColor(calibratedHue: CGFloat((x * 11 + y * 7) % 100) / 100, saturation: 0.35, brightness: 0.6, alpha: 1).setFill()
                NSRect(x: x * 20, y: y * 20, width: 20, height: 20).fill()
            }}
        } else {
            NSColor.white.setFill(); NSRect(x: 50, y: 50, width: 540, height: 300).fill()
            ("Quarterly report  ·  2026" as NSString).draw(at: NSPoint(x: 85, y: 280), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 24), .foregroundColor: NSColor.black])
            for i in 0..<5 { NSColor.systemTeal.setFill(); NSRect(x: 100 + i * 90, y: 90, width: 50, height: 35 + i * 28).fill() }
        }
        return true
    }
    let marked = NSImage(size: size, flipped: false) { rect in
        clean.draw(in: rect)
        ("SAMPLE WATERMARK" as NSString).draw(at: NSPoint(x: kind == 1 ? 160 : 370, y: kind == 1 ? 170 : 35), withAttributes: [.font: NSFont.boldSystemFont(ofSize: kind == 1 ? 32 : 22), .foregroundColor: NSColor.white.withAlphaComponent(0.55)])
        return true
    }
    try save(clean, "sample-\(kind + 1)-clean.png")
    try save(marked, "sample-\(kind + 1)-watermarked.png")
}
