#!/usr/bin/env swift
// Regenerates App/Assets.xcassets/AppIcon.appiconset. Run from apple/: `swift scripts/gen-icon.swift`
//  * iOS: 1024x1024, fully opaque, square (the system applies the mask).
//  * macOS: the same art on an inset rounded square in a transparent canvas, at every size.
import AppKit

let out = URL(fileURLWithPath: "App/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func art(_ ctx: CGContext, _ rect: CGRect) {
    let colors = [NSColor(red: 0.27, green: 0.20, blue: 0.85, alpha: 1).cgColor,
                  NSColor(red: 0.05, green: 0.65, blue: 0.70, alpha: 1).cgColor] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.maxX, y: rect.minY), options: [])

    let font = NSFont.systemFont(ofSize: rect.width * 0.62, weight: .heavy)
    let rounded = font.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: font.pointSize) } ?? font
    let glyph = NSAttributedString(string: "J", attributes: [.font: rounded, .foregroundColor: NSColor.white])
    let size = glyph.size()
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    glyph.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2 + rect.height * 0.02))
    NSGraphicsContext.restoreGraphicsState()
}

func render(_ px: Int, mac: Bool, alpha: Bool) -> Data {
    let info = alpha ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info)!
    let full = CGRect(x: 0, y: 0, width: px, height: px)
    if mac {
        // macOS grid: 824/1024 body, ~185/1024 corner radius.
        let inset = CGFloat(px) * 100 / 1024
        let body = full.insetBy(dx: inset, dy: inset)
        ctx.addPath(CGPath(roundedRect: body, cornerWidth: body.width * 0.225, cornerHeight: body.width * 0.225, transform: nil))
        ctx.clip()
        art(ctx, body)
    } else {
        art(ctx, full)
    }
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
try render(1024, mac: false, alpha: false).write(to: out.appending(path: "ios-1024.png"))
images.append(["filename": "ios-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"])
for pt in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "mac-\(pt)@\(scale)x.png"
        try render(pt * scale, mac: true, alpha: true).write(to: out.appending(path: name))
        images.append(["filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(pt)x\(pt)"])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: out.appending(path: "Contents.json"))
try #"{ "info" : { "author" : "xcode", "version" : 1 } }"#.write(to: out.deletingLastPathComponent().appending(path: "Contents.json"), atomically: true, encoding: .utf8)
print("wrote \(images.count) icons to \(out.path)")
