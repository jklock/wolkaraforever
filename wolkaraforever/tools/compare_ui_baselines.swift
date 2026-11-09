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
        if expected.bytes != actual.bytes {
            var different = 0
            expected.bytes.withUnsafeBytes { left in
                actual.bytes.withUnsafeBytes { right in
                    for index in 0..<expected.bytes.count where left[index] != right[index] { different += 1 }
                }
            }
            fputs("UI baseline pixels differ for \(name): \(different) RGBA bytes\n", stderr)
            failures += 1
        }
    } catch {
        fputs("UI baseline compare failed for \(name): \(error)\n", stderr)
        failures += 1
    }
}
if failures != 0 { exit(1) }
print("UI baseline comparison passed")
