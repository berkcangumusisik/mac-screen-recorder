#!/usr/bin/env swift
//
// Draws Snaplet's app icon from scratch and writes every size the macOS asset
// catalogue needs.
//
//     swift scripts/make-app-icon.swift
//
// The artwork is generated here rather than checked in as a binary so it can be
// reviewed, tweaked and re-rendered like any other source file. Nothing is
// traced from or based on another product's icon.
//
import AppKit
import CoreGraphics
import Foundation

// MARK: - Palette
//
// The same indigo-to-violet pair the "Studio" presentation preset uses, so the
// icon and the app's own output speak with one voice.

let gradientTop = NSColor(srgbRed: 0.36, green: 0.42, blue: 0.86, alpha: 1)
let gradientBottom = NSColor(srgbRed: 0.62, green: 0.38, blue: 0.78, alpha: 1)

// MARK: - Shapes

/// Superellipse, a close approximation of the continuous corners macOS uses.
/// A plain rounded rectangle reads as visibly "wrong" next to system icons.
func squirclePath(in rect: CGRect, exponent: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2
    let b = rect.height / 2
    let centre = CGPoint(x: rect.midX, y: rect.midY)
    let steps = 720

    for step in 0...steps {
        let t = CGFloat(step) / CGFloat(steps) * 2 * .pi
        let cosT = cos(t)
        let sinT = sin(t)
        let x = centre.x + a * (cosT < 0 ? -1 : 1) * pow(abs(cosT), 2 / exponent)
        let y = centre.y + b * (sinT < 0 ? -1 : 1) * pow(abs(sinT), 2 / exponent)
        if step == 0 {
            path.move(to: CGPoint(x: x, y: y))
        } else {
            path.addLine(to: CGPoint(x: x, y: y))
        }
    }
    path.closeSubpath()
    return path
}

/// One corner of the viewfinder: two straight arms meeting at a rounded elbow.
///
/// Built with the elbow at the local origin and the arms running along the
/// positive axes, then mirrored into whichever corner it belongs to.
func bracketPath(corner: CGRect,
                 armLength: CGFloat,
                 thickness: CGFloat,
                 flipX: Bool,
                 flipY: Bool) -> CGPath {
    let radius = thickness * 0.85

    func place(_ point: CGPoint) -> CGPoint {
        CGPoint(x: corner.minX + (flipX ? corner.width - point.x : point.x),
                y: corner.minY + (flipY ? corner.height - point.y : point.y))
    }

    let start = place(CGPoint(x: 0, y: armLength))
    let elbow = place(.zero)
    let end = place(CGPoint(x: armLength, y: 0))

    let path = CGMutablePath()
    path.move(to: start)
    path.addArc(tangent1End: elbow, tangent2End: end, radius: radius)
    path.addLine(to: end)
    return path.copy(strokingWithWidth: thickness,
                     lineCap: .round,
                     lineJoin: .round,
                     miterLimit: 10)
}

// MARK: - Rendering

/// How much detail the artwork carries.
///
/// Downsampling the full drawing to 16 points turns it into a smudge, so the
/// small sizes are drawn with their own, bolder geometry — fewer elements,
/// thicker strokes, no centre plate. This is the same simplification Apple's
/// own icons make at the Finder and Dock sizes.
struct IconDetail {
    var bracketThickness: CGFloat
    var bracketArm: CGFloat
    var fieldInset: CGFloat
    var plateSide: CGFloat?
    var showsHighlight: Bool

    static func forPixelSize(_ pixels: Int) -> IconDetail {
        switch pixels {
        case ...32:
            // Bold frame only: at this size anything inside it disappears.
            return IconDetail(bracketThickness: 96,
                              bracketArm: 168,
                              fieldInset: 150,
                              plateSide: nil,
                              showsHighlight: false)
        case ...64:
            return IconDetail(bracketThickness: 78,
                              bracketArm: 196,
                              fieldInset: 172,
                              plateSide: 150,
                              showsHighlight: true)
        default:
            return IconDetail(bracketThickness: 54,
                              bracketArm: 150,
                              fieldInset: 196,
                              plateSide: 198,
                              showsHighlight: true)
        }
    }
}

/// Draws the icon at `side` pixels using the geometry in `detail`.
func renderIcon(side: CGFloat, detail: IconDetail) -> CGImage {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(data: nil,
                            width: Int(side),
                            height: Int(side),
                            bitsPerComponent: 8,
                            bytesPerRow: 0,
                            space: colorSpace,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setAllowsAntialiasing(true)
    context.interpolationQuality = .high

    // Apple's macOS grid: the artwork fills 824 of a 1024 canvas, leaving room
    // for the shadow that separates it from the Dock and Finder backgrounds.
    let unit = side / 1024
    let bodySide = 824 * unit
    let body = CGRect(x: (side - bodySide) / 2,
                      y: (side - bodySide) / 2 + 8 * unit,
                      width: bodySide,
                      height: bodySide)
    let shape = squirclePath(in: body)

    // Shadow.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10 * unit),
                      blur: 24 * unit,
                      color: NSColor.black.withAlphaComponent(0.28).cgColor)
    context.addPath(shape)
    context.setFillColor(NSColor.black.cgColor)
    context.fillPath()
    context.restoreGState()

    // Gradient body.
    context.saveGState()
    context.addPath(shape)
    context.clip()
    let gradient = CGGradient(colorsSpace: colorSpace,
                              colors: [gradientTop.cgColor, gradientBottom.cgColor] as CFArray,
                              locations: [0, 1])!
    context.drawLinearGradient(gradient,
                               start: CGPoint(x: body.minX, y: body.maxY),
                               end: CGPoint(x: body.maxX, y: body.minY),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

    if detail.showsHighlight {
        // A soft highlight along the top edge gives the surface some depth
        // without resorting to a glossy overlay.
        let highlight = CGGradient(colorsSpace: colorSpace,
                                   colors: [NSColor.white.withAlphaComponent(0.22).cgColor,
                                            NSColor.white.withAlphaComponent(0).cgColor] as CFArray,
                                   locations: [0, 1])!
        context.drawLinearGradient(highlight,
                                   start: CGPoint(x: body.midX, y: body.maxY),
                                   end: CGPoint(x: body.midX, y: body.midY),
                                   options: [])
    }
    context.restoreGState()

    // Viewfinder brackets.
    let field = body.insetBy(dx: detail.fieldInset * unit, dy: detail.fieldInset * unit)
    context.setFillColor(NSColor.white.cgColor)
    for (flipX, flipY) in [(false, false), (true, false), (false, true), (true, true)] {
        let path = bracketPath(corner: field,
                               armLength: detail.bracketArm * unit,
                               thickness: detail.bracketThickness * unit,
                               flipX: flipX,
                               flipY: flipY)
        context.addPath(path)
        context.fillPath()
    }

    // The captured frame sitting inside the viewfinder.
    if let plateSide = detail.plateSide {
        let plate = CGRect(x: field.midX - plateSide * unit / 2,
                           y: field.midY - plateSide * unit / 2,
                           width: plateSide * unit,
                           height: plateSide * unit)
        context.setFillColor(NSColor.white.withAlphaComponent(0.94).cgColor)
        context.addPath(CGPath(roundedRect: plate,
                               cornerWidth: plate.width * 0.26,
                               cornerHeight: plate.height * 0.26,
                               transform: nil))
        context.fillPath()
    }

    return context.makeImage()!
}

func downsample(_ image: CGImage, to side: Int) -> CGImage {
    guard image.width != side else { return image }
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(data: nil,
                            width: side,
                            height: side,
                            bitsPerComponent: 8,
                            bytesPerRow: 0,
                            space: colorSpace,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
    return context.makeImage()!
}

/// Renders at four times the target and downsamples, which anti-aliases the
/// curves far better than drawing straight into a 16-pixel bitmap.
func icon(atPixelSize pixels: Int) -> CGImage {
    let detail = IconDetail.forPixelSize(pixels)
    let supersampled = renderIcon(side: CGFloat(max(pixels * 4, 256)), detail: detail)
    return downsample(supersampled, to: pixels)
}

func write(_ image: CGImage, to url: URL) throws {
    let representation = NSBitmapImageRep(cgImage: image)
    representation.size = NSSize(width: image.width, height: image.height)
    guard let data = representation.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "make-app-icon", code: 1)
    }
    try data.write(to: url)
}

// MARK: - Output

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconSet = root.appendingPathComponent("Snaplet/Resources/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)

/// (point size, scale) pairs required by a macOS app icon.
let variants: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2),
    (128, 1), (128, 2), (256, 1), (256, 2),
    (512, 1), (512, 2)
]

var entries: [[String: String]] = []

for variant in variants {
    let pixels = variant.points * variant.scale
    let name = "icon_\(variant.points)x\(variant.points)\(variant.scale == 2 ? "@2x" : "").png"
    try write(icon(atPixelSize: pixels), to: iconSet.appendingPathComponent(name))
    entries.append([
        "filename": name,
        "idiom": "mac",
        "scale": "\(variant.scale)x",
        "size": "\(variant.points)x\(variant.points)"
    ])
    print("wrote \(name) (\(pixels)px)")
}

let contents: [String: Any] = [
    "images": entries,
    "info": ["author": "xcode", "version": 1]
]
let json = try JSONSerialization.data(withJSONObject: contents,
                                      options: [.prettyPrinted, .sortedKeys])
try json.write(to: iconSet.appendingPathComponent("Contents.json"))
print("wrote Contents.json")

// A 1024 preview for design review; not part of the catalogue.
try FileManager.default.createDirectory(at: root.appendingPathComponent("build"),
                                        withIntermediateDirectories: true)
try write(icon(atPixelSize: 1024), to: root.appendingPathComponent("build/icon-preview.png"))
print("wrote build/icon-preview.png")
