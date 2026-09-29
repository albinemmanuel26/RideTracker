import AppKit
import CoreText
// Uses the same Material Icons glyph as Icons.directions_bike in Flutter.
let root = CommandLine.arguments[1]
let fontURL = URL(fileURLWithPath: CommandLine.arguments[2])
let descriptor = (CTFontManagerCreateFontDescriptorsFromURL(fontURL as CFURL)! as! [CTFontDescriptor])[0]
let font = CTFontCreateWithFontDescriptor(descriptor, 1000, nil)
var character: UniChar = 0xe1d2
var glyph: CGGlyph = 0
precondition(CTFontGetGlyphsForCharacters(font, &character, &glyph, 1))
let path = CTFontCreatePathForGlyph(font, glyph, nil)!
let bounds = path.boundingBoxOfPath
func render(_ relative: String, _ size: Int, _ fraction: CGFloat, _ background: Bool) throws {
 let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
 NSGraphicsContext.saveGraphicsState()
 NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
 let ctx = NSGraphicsContext.current!.cgContext
 let side = CGFloat(size)
 if background {
  ctx.setFillColor(NSColor(srgbRed: 178/255, green: 34/255, blue: 34/255, alpha: 1).cgColor)
  ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
 }
 let scale = side * fraction / max(bounds.width, bounds.height)
 ctx.translateBy(x: side/2 - bounds.midX * scale, y: side/2 - bounds.midY * scale)
 ctx.scaleBy(x: scale, y: scale)
 ctx.setFillColor(NSColor.white.cgColor); ctx.addPath(path); ctx.fillPath()
 NSGraphicsContext.restoreGraphicsState()
 let url = URL(fileURLWithPath: root + "/" + relative)
 try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
 if background {
  let opaque = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
  opaque.draw(rep.cgImage!, in: CGRect(x: 0, y: 0, width: size, height: size))
  let output = NSBitmapImageRep(cgImage: opaque.makeImage()!)
  try output.representation(using: .png, properties: [:])!.write(to: url)
 } else {
  try rep.representation(using: .png, properties: [:])!.write(to: url)
 }
}
try render("assets/branding/ride_track.png", 1024, 0.56, true)
for (density, size) in [("mdpi",48),("hdpi",72),("xhdpi",96),("xxhdpi",144),("xxxhdpi",192)] {
 try render("android/app/src/main/res/mipmap-\(density)/ic_launcher.png", size, 0.56, true)
 let factor = Double(size)/48
 try render("android/app/src/main/res/drawable-\(density)/splash_bike.png", Int(192*factor), 0.5, false)
}
for scale in 1...3 {
 let suffix = scale == 1 ? "" : "@\(scale)x"
 try render("ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage\(suffix).png", 192*scale, 0.5, false)
}
let folder = "ios/Runner/Assets.xcassets/AppIcon.appiconset/"
let data = try Data(contentsOf: URL(fileURLWithPath: root + "/" + folder + "Contents.json"))
let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
for entry in json["images"] as! [[String: Any]] {
 if let name = entry["filename"] as? String {
  let dimension = Double((entry["size"] as! String).split(separator: "x")[0])!
  let scale = Double((entry["scale"] as! String).dropLast())!
  try render(folder + name, Int((dimension*scale).rounded()), 0.56, true)
 }
}
