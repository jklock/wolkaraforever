import Foundation
import CryptoKit
import ZIPFoundation

/// A bundled add-on package: one versioned ZIP of an add-on's folder, and the JSON
/// manifest that says which release it is, what it must hash to, and what each of its
/// files must hash to.
///
/// The archive and the manifest are committed in the layer and shipped in the app, and a
/// fixture rebuilds both from `addons/` and compares, so "the package the app installs"
/// and "the sources that were reviewed" cannot drift apart. Verification is the other
/// half: a package that is not exactly the one recorded is refused, never extracted
/// partially, and the caller is told which of the two files failed.
@objc(TKAddonPackage)
final class TKAddonPackage: NSObject {
    static let format = "wolkaraforever.addon"
    static let formatVersion = 1
    /// Every entry lives under this one folder, so installing the archive is copying a
    /// folder into the game's `Interface/AddOns` and nothing else.
    static let folder = "WolkaraRoue"

    private struct Manifest {
        let name: String
        let release: String
        let archive: String
        let sha256: String
        let files: [String: (size: UInt64, sha256: String)]
    }

    private static func fail(_ message: String, _ output: NSErrorPointer) -> Bool {
        output?.pointee = NSError(domain: "WolkaraForever.AddOns", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: message])
        return false
    }

    private static func hash(of url: URL) -> String? {
        guard let stream = InputStream(url: url) else { return nil }
        stream.open()
        defer { stream.close() }
        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: 1 << 16)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read < 0 { return nil }
            if read == 0 { break }
            hasher.update(data: Data(buffer[0..<read]))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func readManifest(_ url: URL, _ output: NSErrorPointer) -> Manifest? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            _ = fail("The add-on manifest is missing or is not readable JSON.", output)
            return nil
        }
        guard object["format"] as? String == format,
              object["version"] as? Int == formatVersion,
              let name = object["name"] as? String,
              let release = object["release"] as? String,
              let archive = object["archive"] as? String,
              let sha256 = object["sha256"] as? String,
              let files = object["files"] as? [String: Any] else {
            _ = fail("The add-on manifest is not one this app wrote.", output)
            return nil
        }
        var entries: [String: (size: UInt64, sha256: String)] = [:]
        for (path, value) in files {
            guard let file = value as? [String: Any],
                  let size = file["size"] as? UInt64 ?? (file["size"] as? Int).map(UInt64.init),
                  let digest = file["sha256"] as? String,
                  path.hasPrefix("\(folder)/"), !path.contains(".."), !path.hasPrefix("/") else {
                _ = fail("The add-on manifest names a file it could not have recorded.", output)
                return nil
            }
            entries[path] = (size, digest)
        }
        guard !entries.isEmpty else {
            _ = fail("The add-on manifest lists no files.", output)
            return nil
        }
        return Manifest(name: name, release: release, archive: archive, sha256: sha256, files: entries)
    }

    /// Whether the archive at `archiveURL` is exactly the package its manifest describes,
    /// at the release this build expects. Refuses a missing, unreadable, foreign, wrong
    /// release, wrongly hashed, or differently shaped package; nothing is extracted here.
    @objc(verifyArchiveAtURL:manifestAtURL:expectedRelease:error:)
    static func verify(archive archiveURL: URL, manifest manifestURL: URL,
                       expectedRelease: String, error output: NSErrorPointer) -> Bool {
        guard let manifest = readManifest(manifestURL, output) else { return false }
        guard manifest.name == folder else {
            return fail("That manifest belongs to another add-on.", output)
        }
        guard manifest.release == expectedRelease else {
            return fail("The bundled add-on is release \(manifest.release), not \(expectedRelease).",
                        output)
        }
        guard manifest.archive == archiveURL.lastPathComponent else {
            return fail("That manifest belongs to another archive.", output)
        }
        // A package is a regular file: a link must not make the app read a ZIP from
        // somewhere else and call it the bundled one.
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: archiveURL.path),
              attributes[.type] as? FileAttributeType == .typeRegular else {
            return fail("The add-on archive is missing.", output)
        }
        guard hash(of: archiveURL) == manifest.sha256 else {
            return fail("The add-on archive is not the one this app shipped.", output)
        }
        let archive: Archive
        do { archive = try Archive(url: archiveURL, accessMode: .read) }
        catch { return fail("The add-on archive is not a readable ZIP.", output) }

        var seen = Set<String>()
        var measured = 0
        for entry in archive {
            guard entry.type == .file else {
                return fail("The add-on archive contains an entry that is not a file.", output)
            }
            guard entry.path.hasPrefix("\(folder)/"), !entry.path.contains(".."),
                  !entry.path.hasPrefix("/") else {
                return fail("The add-on archive contains a path outside its folder.", output)
            }
            let key = entry.path.precomposedStringWithCanonicalMapping.lowercased()
            guard seen.insert(key).inserted else {
                return fail("The add-on archive contains colliding paths.", output)
            }
            guard let expected = manifest.files[entry.path],
                  expected.size == entry.uncompressedSize else {
                return fail("The add-on archive does not match its manifest.", output)
            }
            var hasher = SHA256()
            var written: UInt64 = 0
            _ = try? archive.extract(entry, bufferSize: 1 << 16, skipCRC32: false) { chunk in
                written += UInt64(chunk.count)
                hasher.update(data: chunk)
            }
            let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            guard written == expected.size, digest == expected.sha256 else {
                return fail("The add-on archive failed its integrity check.", output)
            }
            measured += 1
        }
        guard measured == manifest.files.count else {
            return fail("The add-on archive is missing files its manifest names.", output)
        }
        return true
    }
}
