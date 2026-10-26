#!/usr/bin/env swift
// Regenerates App/Assets.xcassets/AppIcon.appiconset. Run from apple/: `swift scripts/gen-icon.swift`
//  * iOS: 1024x1024, fully opaque, square (the system applies the mask).
//  * macOS: the same art on an inset rounded square in a transparent canvas, at every size.
import AppKit

let out = URL(fileURLWithPath: "App/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func art(_ ctx: CGContext, _ rect: CGRect) {
    // Background: deep indigo → teal
    let colors = [NSColor(red: 0.17, green: 0.19, blue: 0.45, alpha: 1).cgColor,
                  NSColor(red: 0.11, green: 0.45, blue: 0.52, alpha: 1).cgColor] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.maxX, y: rect.minY), options: [])

    // Hamster head in a 0…1 unit space (origin bottom-left): flat, two-tone, no outlines
    let u = rect.width
    func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: rect.minX + (x - w / 2) * u, y: rect.minY + (y - h / 2) * u, width: w * u, height: h * u)
    }
    func oval(_ r: CGRect, _ color: NSColor) {
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: r)
    }
    let fur = NSColor(red: 0.95, green: 0.70, blue: 0.45, alpha: 1)
    let furShade = NSColor(red: 0.84, green: 0.56, blue: 0.34, alpha: 1)
    let cream = NSColor(red: 0.99, green: 0.94, blue: 0.87, alpha: 1)
    let ink = NSColor(red: 0.13, green: 0.10, blue: 0.11, alpha: 1)

    // Ears
    for x in [0.355, 0.645] as [CGFloat] {
        oval(box(x, 0.715, 0.13, 0.14), fur)
        oval(box(x, 0.712, 0.065, 0.075), furShade)
    }
    // Head: a crown plus two full cheeks → the hamster's pear shape
    let head = CGMutablePath()
    head.addEllipse(in: box(0.50, 0.545, 0.46, 0.40))
    head.addEllipse(in: box(0.33, 0.405, 0.40, 0.36))
    head.addEllipse(in: box(0.67, 0.405, 0.40, 0.36))
    head.addEllipse(in: box(0.50, 0.35, 0.56, 0.30))
    ctx.addPath(head)
    ctx.setFillColor(fur.cgColor)
    ctx.fillPath(using: .winding)
    // Cream jaw and cheeks, clipped to the head
    ctx.saveGState()
    ctx.addPath(head)
    ctx.clip(using: .winding)
    oval(box(0.325, 0.36, 0.28, 0.22), cream) // cheek pouches
    oval(box(0.675, 0.36, 0.28, 0.22), cream)
    oval(box(0.50, 0.305, 0.36, 0.18), cream) // chin
    oval(box(0.50, 0.435, 0.19, 0.17), cream) // muzzle
    ctx.restoreGState()
    // Eyes
    for x in [0.40, 0.60] as [CGFloat] {
        oval(box(x, 0.53, 0.050, 0.058), ink)
        oval(box(x - 0.010, 0.543, 0.016, 0.016), NSColor(white: 1, alpha: 0.9))
    }
    // Nose
    oval(box(0.50, 0.47, 0.040, 0.027), NSColor(red: 0.80, green: 0.45, blue: 0.48, alpha: 1))
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
