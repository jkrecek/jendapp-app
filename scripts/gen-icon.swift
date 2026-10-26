#!/usr/bin/env swift
// Regenerates App/Assets.xcassets/AppIcon.appiconset. Run from apple/: `swift scripts/gen-icon.swift`
//  * iOS: 1024x1024, fully opaque, square (the system applies the mask).
//  * macOS: the same art on an inset rounded square in a transparent canvas, at every size.
import AppKit

let out = URL(fileURLWithPath: "App/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func art(_ ctx: CGContext, _ rect: CGRect) {
    // Background: soft sky gradient
    let colors = [NSColor(red: 0.42, green: 0.36, blue: 0.93, alpha: 1).cgColor,
                  NSColor(red: 0.30, green: 0.78, blue: 0.86, alpha: 1).cgColor] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.maxX, y: rect.minY), options: [])

    // Hamster, drawn in a 0…1 unit space (origin bottom-left)
    let u = rect.width
    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * u, y: rect.minY + y * u) }
    func oval(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: NSColor) {
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: CGRect(x: rect.minX + (x - w / 2) * u, y: rect.minY + (y - h / 2) * u, width: w * u, height: h * u))
    }
    let fur = NSColor(red: 0.96, green: 0.66, blue: 0.33, alpha: 1)
    let furDark = NSColor(red: 0.86, green: 0.52, blue: 0.22, alpha: 1)
    let cream = NSColor(red: 1.00, green: 0.95, blue: 0.86, alpha: 1)
    let pink = NSColor(red: 0.97, green: 0.62, blue: 0.70, alpha: 1)
    let ink = NSColor(red: 0.16, green: 0.11, blue: 0.10, alpha: 1)

    // Soft shadow under the body
    oval(0.50, 0.08, 0.80, 0.10, NSColor(white: 0, alpha: 0.12))
    // Ears (behind the body)
    for x in [0.27, 0.73] as [CGFloat] {
        oval(x, 0.72, 0.20, 0.20, furDark)
        oval(x, 0.72, 0.12, 0.12, pink)
    }
    // Body / head: one chubby blob
    oval(0.50, 0.42, 0.80, 0.68, fur)
    // Cream face + belly
    oval(0.50, 0.34, 0.60, 0.50, cream)
    oval(0.33, 0.45, 0.26, 0.20, cream) // puffy cheeks
    oval(0.67, 0.45, 0.26, 0.20, cream)
    // Eyes with highlights
    for x in [0.38, 0.62] as [CGFloat] {
        oval(x, 0.53, 0.085, 0.095, ink)
        oval(x - 0.017, 0.555, 0.030, 0.030, .white)
        oval(x + 0.020, 0.515, 0.013, 0.013, .white)
    }
    // Blush
    oval(0.27, 0.43, 0.11, 0.065, pink.withAlphaComponent(0.75))
    oval(0.73, 0.43, 0.11, 0.065, pink.withAlphaComponent(0.75))
    // Nose
    oval(0.50, 0.475, 0.050, 0.034, NSColor(red: 0.90, green: 0.45, blue: 0.55, alpha: 1))
    // Mouth: a little "w"
    ctx.setStrokeColor(ink.cgColor)
    ctx.setLineWidth(0.011 * u)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.beginPath()
    ctx.move(to: pt(0.455, 0.445))
    ctx.addQuadCurve(to: pt(0.50, 0.445), control: pt(0.477, 0.415))
    ctx.addQuadCurve(to: pt(0.545, 0.445), control: pt(0.523, 0.415))
    ctx.strokePath()
    // Sunflower seed held in two paws
    ctx.saveGState()
    ctx.translateBy(x: pt(0.50, 0.30).x, y: pt(0.50, 0.30).y)
    ctx.rotate(by: -0.35)
    let seed = CGRect(x: -0.05 * u, y: -0.085 * u, width: 0.10 * u, height: 0.17 * u)
    ctx.setFillColor(NSColor(red: 0.28, green: 0.25, blue: 0.27, alpha: 1).cgColor)
    ctx.fillEllipse(in: seed)
    ctx.setStrokeColor(NSColor(white: 0.92, alpha: 1).cgColor)
    ctx.setLineWidth(0.010 * u)
    for dx in [-0.022, 0.022] as [CGFloat] {
        ctx.beginPath()
        ctx.move(to: CGPoint(x: dx * u, y: -0.06 * u))
        ctx.addLine(to: CGPoint(x: dx * u, y: 0.06 * u))
        ctx.strokePath()
    }
    ctx.restoreGState()
    oval(0.43, 0.26, 0.10, 0.075, furDark)
    oval(0.57, 0.26, 0.10, 0.075, furDark)
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
