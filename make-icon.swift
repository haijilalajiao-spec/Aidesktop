import AppKit
import Foundation

let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let inset = size * 0.06
    let body = rect.insetBy(dx: inset, dy: inset)
    let radius = size * 0.22

    let path = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.30, green: 0.42, blue: 0.99, alpha: 1),
        NSColor(calibratedRed: 0.78, green: 0.35, blue: 0.36, alpha: 1)
    ])!
    gradient.draw(in: path, angle: -55)

    // subtle grid of dots
    NSColor.white.withAlphaComponent(0.10).setFill()
    let dot = size * 0.018
    let step = size * 0.09
    for x in stride(from: body.minX + step, to: body.maxX - step, by: step) {
        for y in stride(from: body.minY + step, to: body.maxY - step, by: step) {
            NSBezierPath(ovalIn: NSRect(x: x, y: y, width: dot, height: dot)).fill()
        }
    }

    // center panel
    let panel = NSRect(x: body.midX - size * 0.27, y: body.midY - size * 0.20,
                       width: size * 0.54, height: size * 0.40)
    let panelPath = NSBezierPath(roundedRect: panel, xRadius: size * 0.07, yRadius: size * 0.07)
    NSColor.white.withAlphaComponent(0.18).setFill()
    panelPath.fill()
    NSColor.white.withAlphaComponent(0.35).setStroke()
    panelPath.lineWidth = size * 0.012
    panelPath.stroke()

    // "AI" text
    let text = "AI" as NSString
    let font = NSFont.systemFont(ofSize: size * 0.30, weight: .bold)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white
    ]
    let textSize = text.size(withAttributes: attrs)
    text.draw(at: NSPoint(x: rect.midX - textSize.width / 2,
                          y: rect.midY - textSize.height / 2), withAttributes: attrs)

    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, to url: URL, pixelSize: Int) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else { return }
    rep.size = NSSize(width: pixelSize, height: pixelSize)
    if let data = rep.representation(using: .png, properties: [:]) {
        try? data.write(to: url)
    }
}

let specs: [(Int, String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png")
]

for (px, name) in specs {
    let image = drawIcon(size: CGFloat(px))
    writePNG(image, to: URL(fileURLWithPath: outputDir).appendingPathComponent(name), pixelSize: px)
}
print("iconset written to \(outputDir)")
