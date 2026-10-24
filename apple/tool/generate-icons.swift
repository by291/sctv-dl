// Run from the repository root: swift apple/tool/generate-icons.swift
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let catalog = root.appendingPathComponent("Apps/Shared/Assets.xcassets")
let icons = catalog.appendingPathComponent("AppIcon.appiconset")
try FileManager.default.createDirectory(at: icons, withIntermediateDirectories: true)

func writeJSON(_ value: [String: Any], to url: URL) throws {
    var data = try JSONSerialization.data(
        withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
    data.append(0x0A)
    try data.write(to: url)
}

func render(size: Int, mac: Bool, to url: URL) throws {
    let alpha = mac ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
        let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
            space: space, bitmapInfo: alpha.rawValue)
    else { throw CocoaError(.fileWriteUnknown) }

    context.scaleBy(x: CGFloat(size) / 108, y: CGFloat(size) / 108)
    if mac {
        // Mac artwork includes its own margin and silhouette; iOS applies the system mask.
        context.translateBy(x: 10, y: 10)
        context.scaleBy(x: 88.0 / 108, y: 88.0 / 108)
    }
    // Match the light appearance accent in PresentationStyle.
    context.setFillColor(CGColor(srgbRed: 0.70, green: 0.24, blue: 0.14, alpha: 1))
    context.addPath(
        CGPath(
            roundedRect: CGRect(x: 0, y: 0, width: 108, height: 108),
            cornerWidth: mac ? 24 : 0, cornerHeight: mac ? 24 : 0, transform: nil))
    context.fillPath()

    // Reuse the television and play mark from the Flutter launcher artwork.
    context.setStrokeColor(CGColor(gray: 1, alpha: 1))
    context.setLineWidth(5)
    context.setLineCap(.round)
    context.addPath(
        CGPath(
            roundedRect: CGRect(x: 24, y: 29, width: 60, height: 43),
            cornerWidth: 7, cornerHeight: 7, transform: nil))
    context.strokePath()
    context.move(to: CGPoint(x: 42, y: 85))
    context.addLine(to: CGPoint(x: 54, y: 73))
    context.addLine(to: CGPoint(x: 68, y: 88))
    context.strokePath()
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.move(to: CGPoint(x: 48, y: 40))
    context.addLine(to: CGPoint(x: 48, y: 62))
    context.addLine(to: CGPoint(x: 66, y: 51))
    context.closePath()
    context.fillPath()

    guard let image = context.makeImage(),
        let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    else { throw CocoaError(.fileWriteUnknown) }
    try png.write(to: url)
}

let info: [String: Any] = ["author": "xcode", "version": 1]
var images: [[String: String]] = [
    ["filename": "AppIcon-iOS.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"]
]
try render(size: 1024, mac: false, to: icons.appendingPathComponent("AppIcon-iOS.png"))
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let filename = "AppIcon-mac-\(points)@\(scale)x.png"
        images.append([
            "filename": filename, "idiom": "mac", "size": "\(points)x\(points)",
            "scale": "\(scale)x",
        ])
        try render(size: points * scale, mac: true, to: icons.appendingPathComponent(filename))
    }
}
try writeJSON(["info": info], to: catalog.appendingPathComponent("Contents.json"))
try writeJSON(["images": images, "info": info], to: icons.appendingPathComponent("Contents.json"))
