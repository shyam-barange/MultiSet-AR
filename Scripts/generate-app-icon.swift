#!/usr/bin/env swift
// Renders the three App Icon variants iOS 18+ expects from the brand mark.
//
// The AR-specific idea, per Assets/multiset-ar-asset-production-brief.md, is the
// mark as a survey control point: the brand hexahedron centred in a thin
// registration cross. Two elements, no text, no gradient carrying the design.
//
// Usage: swift Scripts/generate-app-icon.swift <mark.png> <output-dir>

import AppKit
import CoreGraphics
import Foundation

struct Variant {
    let name: String
    let background: CGColor
    let crossColor: CGColor
    let desaturateMark: Bool
}

let side = 1024
let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: generate-app-icon.swift <mark.png> <output-dir>\n".utf8))
    exit(2)
}
let markURL = URL(fileURLWithPath: arguments[1])
let outputDirectory = URL(fileURLWithPath: arguments[2])

guard let markSource = CGImageSourceCreateWithURL(markURL as CFURL, nil),
      let mark = CGImageSourceCreateImageAtIndex(markSource, 0, nil)
else {
    FileHandle.standardError.write(Data("cannot read mark at \(markURL.path)\n".utf8))
    exit(1)
}

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

let variants = [
    Variant(
        name: "AppIcon-Light-Production",
        background: color(0xF5F5F9),
        crossColor: color(0x7C3AED, alpha: 0.32),
        desaturateMark: false
    ),
    Variant(
        name: "AppIcon-Dark-Production",
        background: color(0x1E1B2E),
        crossColor: color(0xA78BFA, alpha: 0.42),
        desaturateMark: false
    ),
    // iOS renders the tinted variant from a single-channel treatment, so a mark
    // relying on multi-colour contrast collapses. Ship it pre-flattened.
    Variant(
        name: "AppIcon-Tinted-Production",
        background: color(0x000000),
        crossColor: color(0xFFFFFF, alpha: 0.28),
        desaturateMark: true
    )
]

func render(_ variant: Variant) throws {
    guard let context = CGContext(
        data: nil,
        width: side,
        height: side,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        // noneSkipLast: opaque output. The asset catalog rejects an alpha channel.
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { throw CocoaError(.fileWriteUnknown) }

    let bounds = CGRect(x: 0, y: 0, width: side, height: side)
    context.setFillColor(variant.background)
    context.fill(bounds)

    // Registration cross: full-bleed hairlines through the centre, plus a ring
    // sized to sit just outside the mark.
    let centre = CGPoint(x: bounds.midX, y: bounds.midY)
    let lineWidth = CGFloat(side) * 0.012
    context.setStrokeColor(variant.crossColor)
    context.setLineWidth(lineWidth)
    context.move(to: CGPoint(x: 0, y: centre.y))
    context.addLine(to: CGPoint(x: bounds.maxX, y: centre.y))
    context.move(to: CGPoint(x: centre.x, y: 0))
    context.addLine(to: CGPoint(x: centre.x, y: bounds.maxY))
    context.strokePath()

    let ringRadius = CGFloat(side) * 0.345
    context.strokeEllipse(in: CGRect(
        x: centre.x - ringRadius,
        y: centre.y - ringRadius,
        width: ringRadius * 2,
        height: ringRadius * 2
    ))

    // The mark, inset so the ring reads as separate from it.
    let markSide = CGFloat(side) * 0.54
    let markRect = CGRect(
        x: centre.x - markSide / 2,
        y: centre.y - markSide / 2,
        width: markSide,
        height: markSide
    )

    var drawn = mark
    if variant.desaturateMark, let grey = desaturated(mark) {
        drawn = grey
    }
    context.setShouldAntialias(true)
    context.interpolationQuality = .high
    context.draw(drawn, in: markRect)

    guard let image = context.makeImage() else { throw CocoaError(.fileWriteUnknown) }
    let url = outputDirectory.appendingPathComponent("\(variant.name).png")
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        "public.png" as CFString,
        1,
        nil
    ) else { throw CocoaError(.fileWriteUnknown) }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    print("wrote \(url.lastPathComponent)  \(side)x\(side)  opaque")
}

/// Luminance-weighted greyscale, keeping the facets distinguishable so the
/// tinted variant still reads as the mark rather than a flat blob.
func desaturated(_ image: CGImage) -> CGImage? {
    let width = image.width
    let height = image.height
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let data = context.data else { return nil }
    let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
    for index in stride(from: 0, to: width * height * 4, by: 4) {
        let r = Double(pixels[index])
        let g = Double(pixels[index + 1])
        let b = Double(pixels[index + 2])
        // Lift the result so mid-violet facets do not crush to near-black.
        let luminance = min(255, 0.2126 * r + 0.7152 * g + 0.0722 * b + 48)
        let value = UInt8(luminance)
        pixels[index] = value
        pixels[index + 1] = value
        pixels[index + 2] = value
    }
    return context.makeImage()
}

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
for variant in variants {
    try render(variant)
}
