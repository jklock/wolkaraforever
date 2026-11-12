import Foundation

/// The fixture for `TKAddonPackage`: the bundled package verifies, and every deliberately
/// wrong package beside it is refused - not extracted, not reported as good.
///
/// The wrong packages are built by `wolkaraforever/tools/package_addon_zip.py --fixtures`,
/// which is also the tool that writes the committed archive and manifest. The names here
/// are the names it writes; each says why that package must be refused, and that reason is
/// what the app's message has to be about.
let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write(Data("usage: test_addon_package <fixtures> <release>\n".utf8))
    exit(2)
}
let fixtures = URL(fileURLWithPath: arguments[1], isDirectory: true)
let release = arguments[2]
let archiveName = "WolkaraRoue-\(release).zip"
let manifestName = "WolkaraRoue-\(release).json"

func run(_ name: String) -> (ok: Bool, message: String) {
    let directory = fixtures.appendingPathComponent(name)
    var error: NSError?
    let ok = TKAddonPackage.verify(archive: directory.appendingPathComponent(archiveName),
                                   manifest: directory.appendingPathComponent(manifestName),
                                   expectedRelease: release, error: &error)
    return (ok, error?.localizedDescription ?? "")
}

var failures = 0
func require(_ name: String, accepted: Bool, mentioning words: [String] = []) {
    let result = run(name)
    if result.ok != accepted {
        FileHandle.standardError.write(Data(
            "FAIL \(name): \(accepted ? "was refused" : "was accepted") - \(result.message)\n".utf8))
        failures += 1
        return
    }
    if !accepted {
        let message = result.message.lowercased()
        for word in words where !message.contains(word.lowercased()) {
            FileHandle.standardError.write(Data(
                "FAIL \(name): message names no \(word): \(result.message)\n".utf8))
            failures += 1
            return
        }
    }
    print("PASS \(name): \(accepted ? "the bundled package verifies" : "refused - \(result.message)")")
}

// The committed package, rebuilt from the reviewed sources, is accepted.
require("good", accepted: true)

// Each of these is a real ZIP of the same add-on, and each is wrong in one way.
require("tampered", accepted: false, mentioning: ["shipped"])
require("truncated", accepted: false, mentioning: ["shipped"])
require("stale-file-hash", accepted: false, mentioning: ["integrity"])
require("missing-file", accepted: false, mentioning: ["manifest"])
require("extra-file", accepted: false, mentioning: ["manifest"])
require("traversal", accepted: false, mentioning: ["outside"])
require("wrong-version", accepted: false, mentioning: ["9.9.9"])
require("no-manifest", accepted: false, mentioning: ["manifest"])
require("absent-archive", accepted: false, mentioning: ["archive"])
require("foreign-manifest", accepted: false, mentioning: ["add-on"])

if failures > 0 {
    FileHandle.standardError.write(Data("ADDON_PACKAGE_FAIL: \(failures) check(s)\n".utf8))
    exit(1)
}
print("ADDON_PACKAGE_PASS: the bundled WolkaraRoue \(release) package verifies and 9 wrong ones are refused")
