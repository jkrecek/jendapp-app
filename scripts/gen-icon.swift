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
    let skin = NSColor(red: 0.96, green: 0.70, blue: 0.70, alpha: 1) // ears, nose, paws

    // Ears
    // Ears: round, thin-rimmed, pink inside
    for x in [0.34, 0.66] as [CGFloat] {
        oval(box(x, 0.71, 0.14, 0.14), fur)
        oval(box(x, 0.708, 0.095, 0.095), skin)
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
    // Darker golden stripe down the forehead
    ctx.saveGState()
    ctx.addPath(head)
    ctx.clip(using: .winding)
    oval(box(0.50, 0.70, 0.11, 0.26), furShade.withAlphaComponent(0.4))
    ctx.restoreGState()
    // Eyes: big, glossy, set wide
    for x in [0.385, 0.615] as [CGFloat] {
        oval(box(x, 0.535, 0.066, 0.072), ink)
        oval(box(x - 0.013, 0.551, 0.022, 0.022), NSColor(white: 1, alpha: 0.92))
    }
    // Nose and split upper lip
    oval(box(0.50, 0.468, 0.042, 0.028), skin)
    ctx.setStrokeColor(furShade.cgColor)
    ctx.setLineWidth(0.008 * u)
    ctx.setLineCap(.round)
    let lip = CGMutablePath()
    lip.move(to: CGPoint(x: rect.minX + 0.50 * u, y: rect.minY + 0.455 * u))
    lip.addLine(to: CGPoint(x: rect.minX + 0.50 * u, y: rect.minY + 0.425 * u))
    lip.move(to: CGPoint(x: rect.minX + 0.47 * u, y: rect.minY + 0.41 * u))
    lip.addQuadCurve(to: CGPoint(x: rect.minX + 0.50 * u, y: rect.minY + 0.425 * u), control: CGPoint(x: rect.minX + 0.485 * u, y: rect.minY + 0.41 * u))
    lip.addQuadCurve(to: CGPoint(x: rect.minX + 0.53 * u, y: rect.minY + 0.41 * u), control: CGPoint(x: rect.minX + 0.515 * u, y: rect.minY + 0.41 * u))
    ctx.addPath(lip)
    ctx.strokePath()
    // Whiskers
    ctx.setStrokeColor(NSColor(red: 0.62, green: 0.42, blue: 0.30, alpha: 0.55).cgColor)
    ctx.setLineWidth(0.006 * u)
    for side in [-1.0, 1.0] as [CGFloat] {
        for (dy, tilt) in [(0.02, 0.05), (0.0, 0.0), (-0.02, -0.05)] as [(CGFloat, CGFloat)] {
            let w = CGMutablePath()
            w.move(to: CGPoint(x: rect.minX + (0.50 + side * 0.07) * u, y: rect.minY + (0.445 + dy) * u))
            w.addQuadCurve(to: CGPoint(x: rect.minX + (0.50 + side * 0.30) * u, y: rect.minY + (0.445 + dy + tilt) * u),
                           control: CGPoint(x: rect.minX + (0.50 + side * 0.19) * u, y: rect.minY + (0.455 + dy + tilt * 0.4) * u))
            ctx.addPath(w)
        }
    }
    ctx.strokePath()
    // Little pink paws tucked under the chin
    for x in [0.445, 0.555] as [CGFloat] {
        oval(box(x, 0.245, 0.075, 0.055), skin)
        for t in [-0.022, 0.0, 0.022] as [CGFloat] {
            oval(box(x + t, 0.268, 0.020, 0.020), skin)
        }
    }
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
