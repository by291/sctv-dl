// Run on macOS with `swift tool/generate_icons.swift` from flutter/.
// The same geometric mark is rendered at native launcher asset sizes.
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconDirectory = root.appendingPathComponent("ios/Runner/Assets.xcassets/AppIcon.appiconset")
let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: iconDirectory.appendingPathComponent("Contents.json"))) as! [String: Any]
let images = manifest["images"] as! [[String: String]]
var destinations: [URL: Int] = [:]
for image in images {
  let points = Double(image["size"]!.split(separator: "x")[0])!
  let scale = Double(image["scale"]!.dropLast())!
  destinations[iconDirectory.appendingPathComponent(image["filename"]!)] = Int(points * scale)
}
for (density, size) in ["mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192] {
  destinations[root.appendingPathComponent("android/app/src/main/res/mipmap-\(density)/ic_launcher.png")] = size
}
for (destination, size) in destinations {
  let space = CGColorSpace(name: CGColorSpace.sRGB)!
  let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                          bytesPerRow: size * 4, space: space,
                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
  context.scaleBy(x: CGFloat(size) / 108, y: CGFloat(size) / 108)
  context.setFillColor(CGColor(colorSpace: space, components: [107.0 / 255, 170.0 / 255, 217.0 / 255, 1])!)
  context.fill(CGRect(x: 0, y: 0, width: 108, height: 108))
  context.setStrokeColor(CGColor(gray: 1, alpha: 1))
  context.setLineWidth(5)
  context.setLineCap(.round)
  context.addPath(CGPath(roundedRect: CGRect(x: 24, y: 29, width: 60, height: 43),
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
  let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
  try bitmap.representation(using: .png, properties: [:])!.write(to: destination)
}
