import CoreGraphics
import Foundation
import ImageIO

struct PixelImage {
    let width: Int
    let height: Int
    let bytes: Data
}

func load(_ path: String) throws -> PixelImage {
    let url = URL(fileURLWithPath: path)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw NSError(domain: "UIBaseline", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "cannot decode \(path)"])
    }
    let width = image.width
    let height = image.height
    var bytes = Data(count: width * height * 4)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let drew = bytes.withUnsafeMutableBytes { raw -> Bool in
        guard let context = CGContext(data: raw.baseAddress, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return false
        }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    guard drew else { throw NSError(domain: "UIBaseline", code: 2) }
    return PixelImage(width: width, height: height, bytes: bytes)
}

// A channel difference at or below this is renderer rounding, not a change. Measured between
// two identical iPhone runs on 2026-11-09: 1/255 along a nine-pixel hairline on the add-on
// page, 3/255 then 4/255 across a four-pixel-tall band of one German glyph. Anything a person
// could see is far above it - the animating clock and spinner that this check found were 161
// and 110 - and every real change measured so far has been over a far larger area.
let negligibleDelta = 4

let arguments = CommandLine.arguments
guard arguments.count >= 4 else {
    fputs("usage: compare_ui_baselines.swift <expected-dir> <actual-dir> <image>...\n", stderr)
    exit(2)
}
let expectedDirectory = arguments[1]
let actualDirectory = arguments[2]
var failures = 0
for name in arguments.dropFirst(3) {
    let expectedPath = URL(fileURLWithPath: expectedDirectory).appendingPathComponent(name).path
    let actualPath = URL(fileURLWithPath: actualDirectory).appendingPathComponent(name).path
    guard FileManager.default.fileExists(atPath: expectedPath) else {
        fputs("UI baseline missing: \(expectedPath)\n", stderr); failures += 1; continue
    }
    guard FileManager.default.fileExists(atPath: actualPath) else {
        fputs("UI fixture did not capture: \(actualPath)\n", stderr); failures += 1; continue
    }
    do {
        let expected = try load(expectedPath)
        let actual = try load(actualPath)
        guard expected.width == actual.width && expected.height == actual.height else {
            fputs("UI baseline dimensions differ for \(name): expected \(expected.width)x\(expected.height), got \(actual.width)x\(actual.height)\n", stderr)
            failures += 1; continue
        }
        var different = 0
        var pixels = 0
        var worst = 0
        var box = (minX: Int.max, minY: Int.max, maxX: -1, maxY: -1)
        expected.bytes.withUnsafeBytes { left in
            actual.bytes.withUnsafeBytes { right in
                for index in 0..<expected.bytes.count where left[index] != right[index] { different += 1 }
                for pixel in 0..<(expected.width * expected.height) {
                    let offset = pixel * 4
                    var delta = 0
                    for channel in 0..<3 {
                        let difference = abs(Int(left[offset + channel]) - Int(right[offset + channel]))
                        if difference > delta { delta = difference }
                    }
                    if delta > worst { worst = delta }
                    if delta > negligibleDelta {
                        pixels += 1
                        let x = pixel % expected.width, y = pixel / expected.width
                        box.minX = min(box.minX, x); box.maxX = max(box.maxX, x)
                        box.minY = min(box.minY, y); box.maxY = max(box.maxY, y)
                    }
                }
            }
        }
        if pixels > 0 {
            let detail = box.maxX >= 0
                ? "region x\(box.minX)…\(box.maxX) y\(box.minY)…\(box.maxY), worst channel delta \(worst)"
                : "no pixel differs visibly"
            fputs("UI baseline pixels differ for \(name): \(pixels) pixel(s) beyond tolerance (\(different) RGBA bytes); \(detail)\n", stderr)
            failures += 1
        } else if different > 0 {
            // Nothing visible changed; say so rather than silently accepting it.
            print("ok \(name): only \(different) RGBA byte(s) of rounding within tolerance")
        }
    } catch {
        fputs("UI baseline compare failed for \(name): \(error)\n", stderr)
        failures += 1
    }
}
if failures != 0 { exit(1) }
print("UI baseline comparison passed")
