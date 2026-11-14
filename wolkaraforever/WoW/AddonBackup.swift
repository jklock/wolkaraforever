import Foundation
import ZIPFoundation

// Whole-directory add-on backups.
//
// "Backup Add-ons" writes one ZIP of everything under Interface/AddOns - every package folder,
// the manifest that records which of them this app owns, all of it - into the same WTF/Backups
// folder the UI backups use, under an `AddOns-` name. "Restore Add-ons" puts one of those ZIPs
// back, replacing the directory in one swap so a failed restore leaves the folder exactly as it
// was.
//
// This is the whole of add-on backup. It never reads an add-on's Lua, never edits the game's
// files, and never runs on its own: both directions happen because someone pressed the row.
@objc(TKAddonBackupArchive)
final class TKAddonBackupArchive: NSObject {
    /// The name every backup this app writes starts with, and the only kind it will put back.
    private static let prefix = "AddOns-"
    /// The store's own manifest, which lives inside the add-on folder and is part of a backup.
    private static let manifestName = ".wolkaraforever-addons.json"
    private static let fileLimit: UInt64 = 64 * 1024 * 1024
    private static let entryLimit = 20_000

    private static func fail(_ message: String, _ output: NSErrorPointer) {
        output?.pointee = NSError(domain: "WolkaraForever.AddOns", code: 2,
                                  userInfo: [NSLocalizedDescriptionKey: message])
    }

    private static func folder(_ path: String, _ output: NSErrorPointer) -> URL? {
        guard !path.isEmpty else { fail("The add-on folder is not known.", output); return nil }
        let url = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            fail("The add-on folder is missing.", output)
            return nil
        }
        return url
    }

    /// The game's working folder, which is two levels above AddOns: `<working>/Interface/AddOns`.
    private static func workingDirectory(_ addOns: URL, _ output: NSErrorPointer) -> URL? {
        let working = addOns.deletingLastPathComponent().deletingLastPathComponent()
        guard working.path != "/" else {
            fail("The add-on folder is outside the game's working folder.", output)
            return nil
        }
        return working
    }

    /// Where both kinds of backup live: the same `WTF/Backups` the UI backups use, so a person
    /// finds every snapshot in one place.
    private static func backupDirectory(_ working: URL, create: Bool, _ output: NSErrorPointer) -> URL? {
        let directory = working.appendingPathComponent("WTF/Backups", isDirectory: true)
        if create {
            do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
            catch { fail("The backup folder could not be created.", output); return nil }
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            fail("The backup folder is missing.", output)
            return nil
        }
        return directory
    }

    private static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss'Z'"
        return formatter.string(from: Date())
    }

    private static func uniqueName(in directory: URL) -> String {
        let base = prefix + stamp()
        var name = base + ".zip"
        var suffix = 2
        while FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path) {
            name = "\(base)-\(suffix).zip"
            suffix += 1
        }
        return name
    }

    /// A name this class wrote: never a path, never another kind of archive.
    private static func nameIsOurs(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("/") && !name.contains(":") &&
            name.hasPrefix(prefix) && name.hasSuffix(".zip")
    }

    private struct Entry {
        let path: String
        let url: URL
        let isDirectory: Bool
        let size: UInt64
    }

    /// What a backup carries, relative to the add-on folder, in a stable order so two backups of
    /// an unchanged folder list their entries the same way.
    private static func walk(_ addOns: URL, _ output: NSErrorPointer) -> [Entry]? {
        let manager = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey]
        guard let enumerator = manager.enumerator(at: addOns, includingPropertiesForKeys: keys,
                                                  options: [], errorHandler: { _, _ in true }) else {
            fail("The add-on folder could not be read.", output)
            return nil
        }
        let base = addOns.path.hasSuffix("/") ? addOns.path : addOns.path + "/"
        var entries: [Entry] = []
        for case let url as URL in enumerator {
            if url.lastPathComponent == ".DS_Store" { continue }
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            // A link is not followed and not skipped silently: a backup that repeats whatever a
            // link pointed at is not a backup of this folder, so it refuses instead.
            if values.isSymbolicLink == true {
                fail("The add-on folder contains a link, which a backup cannot follow.", output)
                return nil
            }
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(base) else { continue }
            let relative = String(path.dropFirst(base.count))
            guard !relative.isEmpty, !relative.contains(":"),
                  !relative.split(separator: "/", omittingEmptySubsequences: false)
                    .contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else { continue }
            let isDirectory = values.isDirectory == true
            if !isDirectory && values.isRegularFile != true { continue }
            let size = UInt64(values.fileSize ?? 0)
            guard isDirectory || size <= fileLimit else {
                fail("An add-on file is too large to back up.", output)
                return nil
            }
            entries.append(Entry(path: isDirectory ? relative + "/" : relative, url: url,
                                 isDirectory: isDirectory, size: isDirectory ? 0 : size))
            guard entries.count <= entryLimit else {
                fail("The add-on folder has too many entries to back up.", output)
                return nil
            }
        }
        return entries.sorted { $0.path < $1.path }
    }

    /// Write one ZIP of the whole add-on folder, and return its name inside WTF/Backups.
    @objc(createBackupInAddOnsDirectory:error:)
    static func createBackup(addOnsDirectory: String, error output: NSErrorPointer) -> String? {
        guard let addOns = folder(addOnsDirectory, output),
              let working = workingDirectory(addOns, output),
              let backups = backupDirectory(working, create: true, output) else { return nil }
        guard let entries = walk(addOns, output) else { return nil }
        let manager = FileManager.default
        let name = uniqueName(in: backups)
        // Written under a temporary name and moved into place, so a failure part-way through
        // never leaves half an archive under a name a person could pick to restore.
        let temporary = backups.appendingPathComponent(".AddOns-\(UUID().uuidString).tmp.zip")
        defer { try? manager.removeItem(at: temporary) }
        do {
            let archive = try Archive(url: temporary, accessMode: .create)
            let date = Date()
            for entry in entries {
                if entry.isDirectory {
                    try archive.addEntry(with: entry.path, type: .directory, uncompressedSize: Int64(0),
                                         modificationDate: date, permissions: 0o755,
                                         compressionMethod: .none) { _, _ in Data() }
                    continue
                }
                let handle = try FileHandle(forReadingFrom: entry.url)
                defer { try? handle.close() }
                try archive.addEntry(with: entry.path, type: .file, uncompressedSize: Int64(entry.size),
                                     modificationDate: date, permissions: 0o644,
                                     compressionMethod: .deflate) { position, count in
                    try handle.seek(toOffset: UInt64(position))
                    return try handle.read(upToCount: count) ?? Data()
                }
            }
        } catch {
            fail("The backup archive could not be written.", output)
            return nil
        }
        do { try manager.moveItem(at: temporary, to: backups.appendingPathComponent(name)) }
        catch { fail("The backup could not be saved.", output); return nil }
        return name
    }

    /// Every backup this app wrote for this folder, newest first.
    @objc(backupNamesInAddOnsDirectory:error:)
    static func backupNames(addOnsDirectory: String, error output: NSErrorPointer) -> [String] {
        guard let addOns = folder(addOnsDirectory, output),
              let working = workingDirectory(addOns, output),
              let backups = backupDirectory(working, create: false, output) else { return [] }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: backups.path)) ?? []
        return names.filter { nameIsOurs($0) }.sorted(by: >)
    }

    /// Replace the whole add-on folder with the contents of one backup. The swap is one rename
    /// each way: an extract that fails, or a move that fails, leaves the folder as it was.
    ///
    /// The unpacking is `TKAddonArchive`'s, not a second implementation of the same rules: it
    /// already refuses traversal, links, unknown entry types, oversized files and an archive
    /// whose header lies about what it expands to, and it refuses a destination that exists, so
    /// it can only ever write into the fresh staging folder this method names.
    @objc(restoreBackupNamed:inAddOnsDirectory:error:)
    static func restoreBackup(name: String, addOnsDirectory: String, error output: NSErrorPointer) -> Bool {
        guard nameIsOurs(name) else { fail("That file is not an add-on backup.", output); return false }
        guard let addOns = folder(addOnsDirectory, output),
              let working = workingDirectory(addOns, output),
              let backups = backupDirectory(working, create: false, output) else { return false }
        let source = backups.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: source.path) else {
            fail("That backup is no longer there.", output); return false
        }
        let manager = FileManager.default
        let token = UUID().uuidString
        let staging = working.appendingPathComponent(".addon-restore-\(token)", isDirectory: true)
        let replaced = working.appendingPathComponent(".addon-replaced-\(token)", isDirectory: true)
        defer { try? manager.removeItem(at: staging) }
        guard TKAddonArchive.extract(archiveURL: source, to: staging, error: output) else { return false }
        // A backup of an empty folder would replace working add-ons with nothing. Only a folder
        // holding at least one package, or the store's manifest, is allowed back.
        let names = (try? manager.contentsOfDirectory(atPath: staging.path)) ?? []
        let carriesPackages = names.contains(manifestName) || names.contains { item in
            var isDirectory: ObjCBool = false
            return manager.fileExists(atPath: staging.appendingPathComponent(item).path,
                                      isDirectory: &isDirectory) && isDirectory.boolValue
        }
        guard carriesPackages else {
            fail("That backup has no add-ons in it.", output)
            return false
        }
        do { try manager.moveItem(at: addOns, to: replaced) }
        catch { fail("The add-on folder could not be set aside for the restore.", output); return false }
        do {
            try manager.moveItem(at: staging, to: addOns)
        } catch {
            try? manager.moveItem(at: replaced, to: addOns)
            fail("The restored folder could not be put in place.", output)
            return false
        }
        try? manager.removeItem(at: replaced)
        return true
    }
}
