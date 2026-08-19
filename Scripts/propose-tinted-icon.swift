import CoreGraphics
import Foundation
import ImageIO

// iOS tinted mode maps a greyscale source onto the user's chosen colour, so the
// facets must sit at clearly separated grey values. Deriving from the LIGHT
// variant and stretching the mark's own tonal range preserves that separation,
// where a plain luminance pass crushes mid-violets to near-black.
let input = CommandLine.arguments[1]
let output = CommandLine.arguments[2]

guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: input) as CFURL, nil),
      let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { exit(1) }
let w = img.width, h = img.height
var data = [UInt8](repeating: 0, count: w * h * 4)
guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                          bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { exit(1) }
ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))

// Measure the mark's luminance range, ignoring the flat page background.
let cx = w / 2, cy = h / 2, r = Int(Double(min(w, h)) * 0.27)
var lo = 255.0, hi = 0.0
func luma(_ i: Int) -> Double {
    0.2126 * Double(data[i]) + 0.7152 * Double(data[i + 1]) + 0.0722 * Double(data[i + 2])
}
for y in (cy - r)..<(cy + r) {
    for x in (cx - r)..<(cx + r) {
        let dx = x - cx, dy = y - cy
        guard dx * dx + dy * dy <= r * r else { continue }
        let v = luma((y * w + x) * 4)
        lo = min(lo, v); hi = max(hi, v)
    }
}
print(String(format: "mark luminance in source: %.0f...%.0f", lo, hi))

// Stretch that range into 60...235: dark enough to read as the mark, light enough
// that the facets stay distinct once a tint is applied.
let floorOut = 60.0, ceilOut = 235.0
let span = max(hi - lo, 1)
for i in stride(from: 0, to: data.count, by: 4) {
    let v = luma(i)
    let normalised = (v - lo) / span
    let mapped = floorOut + max(0, min(1, normalised)) * (ceilOut - floorOut)
    let out = UInt8(max(0, min(255, mapped)))
    data[i] = out; data[i + 1] = out; data[i + 2] = out
}

guard let result = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: output) as CFURL, "public.png" as CFString, 1, nil)
else { exit(1) }
CGImageDestinationAddImage(dest, result, nil)
guard CGImageDestinationFinalize(dest) else { exit(1) }
print("wrote \(output)")
