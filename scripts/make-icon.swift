#!/usr/bin/env swift
// Erzeugt Resources/AppIcon.icns aus SF Symbols – ausschließlich mit Apple-Frameworks.
// Aufruf: swift scripts/make-icon.swift [Zielordner] [Vorschau-PNG]
//         Standard: Resources und docs/icon.png
import AppKit

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources")
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("ServerPulse-AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let blueTop = NSColor(srgbRed: 0.36, green: 0.64, blue: 1.00, alpha: 1)
let blueBottom = NSColor(srgbRed: 0.15, green: 0.31, blue: 0.86, alpha: 1)
let greenTop = NSColor(srgbRed: 0.42, green: 0.88, blue: 0.47, alpha: 1)
let greenBottom = NSColor(srgbRed: 0.16, green: 0.68, blue: 0.29, alpha: 1)

func symbol(_ name: String, pointSize: CGFloat, weight: NSFont.Weight) -> NSImage? {
    let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
}

func drawCentered(_ image: NSImage, in rect: NSRect, yOffset: CGFloat = 0) {
    let size = image.size
    image.draw(in: NSRect(
        x: rect.midX - size.width / 2,
        y: rect.midY - size.height / 2 + yOffset,
        width: size.width,
        height: size.height
    ))
}

func render(pixels: Int) -> Data {
    let side = CGFloat(pixels)
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { fatalError("Bitmap konnte nicht erzeugt werden") }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

    // macOS-Icon-Raster: Körper 824/1024, Eckenradius ≈ 22 %.
    let inset = side * 100 / 1024
    let body = NSRect(x: inset, y: inset, width: side - 2 * inset, height: side - 2 * inset)
    let radius = body.width * 0.2237
    let shape = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowOffset = NSSize(width: 0, height: -side * 0.012)
    shadow.shadowBlurRadius = side * 0.03
    shadow.set()
    blueBottom.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(starting: blueTop, ending: blueBottom)?.draw(in: shape, angle: -90)

    if let rack = symbol("server.rack", pointSize: body.width * 0.44, weight: .medium) {
        drawCentered(rack, in: body, yOffset: body.height * 0.03)
    }

    // Grüner Status-Badge mit Puls-Linie unten rechts.
    let diameter = body.width * 0.30
    let badge = NSRect(x: body.maxX - diameter - body.width * 0.07,
                       y: body.minY + body.width * 0.07,
                       width: diameter, height: diameter)
    NSColor.white.setFill()
    NSBezierPath(ovalIn: badge.insetBy(dx: -diameter * 0.09, dy: -diameter * 0.09)).fill()
    NSGradient(starting: greenTop, ending: greenBottom)?.draw(in: NSBezierPath(ovalIn: badge), angle: -90)
    if let pulse = symbol("waveform.path.ecg", pointSize: diameter * 0.46, weight: .bold) {
        drawCentered(pulse, in: badge)
    }

    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("PNG-Export fehlgeschlagen") }
    return png
}

let variants: [(pixels: Int, name: String)] = [
    (16, "16x16"), (32, "16x16@2x"), (32, "32x32"), (64, "32x32@2x"),
    (128, "128x128"), (256, "128x128@2x"), (256, "256x256"), (512, "256x256@2x"),
    (512, "512x512"), (1024, "512x512@2x")
]
for variant in variants {
    try render(pixels: variant.pixels).write(to: iconset.appendingPathComponent("icon_\(variant.name).png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", outputDirectory.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil ist fehlgeschlagen") }
let previewPath = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "docs/icon.png"
try? FileManager.default.createDirectory(
    at: URL(fileURLWithPath: previewPath).deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try render(pixels: 1024).write(to: URL(fileURLWithPath: previewPath))
try? FileManager.default.removeItem(at: iconset)
print("✅ \(outputDirectory.appendingPathComponent("AppIcon.icns").path)")
