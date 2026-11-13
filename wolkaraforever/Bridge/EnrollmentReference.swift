import Foundation
import Security

// A reinstall replaces the app container; it does not replace the Keychain.
//
// Enrolment writes two things: the trusted record, which lives in the protected
// Keychain, and the marker the launcher reads (`TKEnrolledDeviceIdentifier` in
// UserDefaults), which lives in the container. Reinstalling the app therefore
// deletes the marker and keeps the record, so the app refuses a launch with
// "not enrolled" while a valid trust pin for exactly this iPad is still there.
//
// This file adds the missing reference. It is a second Keychain item, under a
// fixed account of its own, holding the record's device identifier and the
// record's own public fingerprint. Nothing else: no keys, no pairing material.
// On a launch that still has its marker the reference is (re)derived from the
// verified record, which is what makes it survive a reinstall that happens
// afterwards. On a launch that has lost its marker the reference is used only
// after the record it names is read back and its fingerprint matches, and only
// then is the marker restored.
//
// The reference is never authoritative. A marker that exists is never replaced,
// a record that will not load is never overwritten, a reference that names a
// different record or no record is refused and removed, and a reference that
// cannot be parsed is refused and removed. Every failure leaves the app exactly
// where it was before: the launcher's preflight still says "not enrolled" and
// the user enrols again, which is the safe direction.

// MARK: - What the reference holds

enum EnrollmentReferenceFailure: Error, Equatable {
    case configuration, unavailable, corruptRecord
}

struct EnrollmentReferenceRecord: Equatable {
    static let format = "tolkara-enrollment-reference-v1"
    static let maximumSize = 4_096
    static let fingerprintLength = 32

    let deviceIdentifier: String
    let fingerprint: Data

    // The same identifier rule the helper and the launcher use: a short opaque
    // string from enrolment, not a path, not a log line and never empty.
    static func validIdentifier(_ identifier: String) -> Bool {
        !identifier.isEmpty && identifier.utf8.count <= 1024
            && !identifier.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }

    init(deviceIdentifier: String, fingerprint: Data) throws {
        guard Self.validIdentifier(deviceIdentifier) else { throw PairingError.malformed }
        guard fingerprint.count == Self.fingerprintLength else { throw PairingError.malformed }
        self.deviceIdentifier = deviceIdentifier
        self.fingerprint = fingerprint
    }

    // A record that cannot be read exactly as written is not a reference.
    init(untrustedData: Data) throws {
        guard untrustedData.count <= Self.maximumSize else { throw PairingError.oversized }
        let parsed: Any
        do { parsed = try PropertyListSerialization.propertyList(from: untrustedData, options: [], format: nil) }
        catch { throw PairingError.malformed }
        guard let object = parsed as? [String: Any], object.count == 3,
              object["format"] as? String == Self.format,
              let identifier = object["deviceIdentifier"] as? String,
              let hex = object["fingerprint"] as? String,
              hex.utf8.count == Self.fingerprintLength * 2,
              let fingerprint = Self.decode(hex) else { throw PairingError.malformed }
        try self.init(deviceIdentifier: identifier, fingerprint: fingerprint)
    }

    func serialize() throws -> Data {
        let hex = fingerprint.map { String(format: "%02x", $0) }.joined()
        let data = try PropertyListSerialization.data(fromPropertyList: ["format": Self.format,
            "deviceIdentifier": deviceIdentifier, "fingerprint": hex], format: .binary, options: 0)
        guard data.count <= Self.maximumSize else { throw PairingError.oversized }
        return data
    }

    private static func decode(_ hex: String) -> Data? {
        var bytes = Data(capacity: fingerprintLength)
        var high: UInt8?
        for character in hex.utf8 {
            let value: UInt8
            switch character {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): value = character - UInt8(ascii: "0")
            case UInt8(ascii: "a")...UInt8(ascii: "f"): value = character - UInt8(ascii: "a") + 10
            default: return nil
            }
            if let pending = high { bytes.append(pending << 4 | value); high = nil }
            else { high = value }
        }
        return high == nil && bytes.count == fingerprintLength ? bytes : nil
    }
}

// MARK: - Where the reference lives

// One item, one fixed account, our own service. Looking it up needs no list of
// anything: the account is a constant, so no device identifier and no
// enumeration of the user's keychain is involved.
final class EnrollmentReferenceStore {
    static let service = "local.tolkara.pairing.enrollment.reference.v1"
    static let account = "enrollment-reference"

    private let group: String
    private let backend: PairingKeychainBackend

    init(accessGroup: String, backend: PairingKeychainBackend = SystemPairingKeychain()) throws {
        guard accessGroup.count <= 256, accessGroup.contains("."),
              accessGroup.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 46 })
        else { throw EnrollmentReferenceFailure.configuration }
        group = accessGroup
        self.backend = backend
    }

    convenience init(bundle: Bundle = .main) throws {
        guard let group = bundle.object(forInfoDictionaryKey: "TKPairingKeychainGroup") as? String
        else { throw EnrollmentReferenceFailure.configuration }
        try self.init(accessGroup: group)
    }

    private var base: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: Self.service,
         kSecAttrAccount as String: Self.account,
         kSecAttrAccessGroup as String: group,
         kSecAttrSynchronizable as String: false,
         kSecUseDataProtectionKeychain as String: true]
    }

    // nil is "there is no reference"; a throw is "the reference cannot be
    // trusted", and those two must not be confused: only the first one lets a
    // new reference be derived.
    func read() throws -> Data? {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let (status, value) = backend.copy(query)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw EnrollmentReferenceFailure.unavailable }
        guard let attributes = value as? [String: Any],
              let bytes = attributes[kSecValueData as String] as? Data,
              attributes[kSecAttrAccessible as String] as? String == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String,
              attributes[kSecAttrAccessGroup as String] as? String == group else { throw EnrollmentReferenceFailure.corruptRecord }
        return bytes
    }

    // Replace, never accumulate: the account is fixed, so a second reference
    // would be a second answer to the same question.
    func write(_ data: Data) throws {
        guard data.count <= EnrollmentReferenceRecord.maximumSize else { throw EnrollmentReferenceFailure.unavailable }
        _ = backend.delete(base)
        var query = base
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        query[kSecValueData as String] = data
        guard backend.add(query) == errSecSuccess else { throw EnrollmentReferenceFailure.unavailable }
    }

    func clear() throws {
        let status = backend.delete(base)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw EnrollmentReferenceFailure.unavailable }
    }
}

// MARK: - What to do about it

// The whole policy is one pure decision, so the tests read the same function the
// app runs and every branch is a value rather than a log line.
enum EnrollmentReferenceRefusal: String, Equatable {
    case invalidMarker = "invalid-marker"
    case recordUnavailable = "record-unavailable"
    case staleReference = "stale-reference"
    case fingerprintMismatch = "fingerprint-mismatch"
    case malformedReference = "malformed-reference"
    case storageUnavailable = "storage-unavailable"
}

enum EnrollmentReferenceDecision: Equatable {
    case nothing          // nothing to do on either side
    case current          // the marker and the reference already agree
    case writeReference(EnrollmentReferenceRecord)   // derive or repair the reference from the record
    case restoreMarker(String)                       // the reference and the record agree; restore the marker
    case refuse(EnrollmentReferenceRefusal)
}

protocol EnrollmentReferenceRecords {
    func record(deviceIdentifier: String) throws -> PairingEnrollment?
}

extension PairingKeychain: EnrollmentReferenceRecords {
    func record(deviceIdentifier: String) throws -> PairingEnrollment? {
        try load(deviceIdentifier: deviceIdentifier)
    }
}

struct EnrollmentReferenceResolver {
    let records: EnrollmentReferenceRecords

    func decide(marker: String?, reference: Data?) -> EnrollmentReferenceDecision {
        if let marker = marker, !marker.isEmpty {
            guard EnrollmentReferenceRecord.validIdentifier(marker) else { return .refuse(.invalidMarker) }
            // A marker is only ever kept, and a reference is only ever derived
            // from the record that marker names. Trust is not read from the
            // reference while the marker exists.
            do {
                guard let record = try records.record(deviceIdentifier: marker) else { return .refuse(.recordUnavailable) }
                let wanted = try EnrollmentReferenceRecord(deviceIdentifier: record.deviceIdentifier, fingerprint: record.fingerprint)
                if let reference = reference,
                   let existing = try? EnrollmentReferenceRecord(untrustedData: reference), existing == wanted { return .current }
                return .writeReference(wanted)
            } catch { return .refuse(.recordUnavailable) }
        }
        guard let reference = reference else { return .nothing }
        guard let parsed = try? EnrollmentReferenceRecord(untrustedData: reference) else { return .refuse(.malformedReference) }
        do {
            guard let record = try records.record(deviceIdentifier: parsed.deviceIdentifier) else { return .refuse(.staleReference) }
            let actual = try EnrollmentReferenceRecord(deviceIdentifier: record.deviceIdentifier, fingerprint: record.fingerprint)
            guard actual.fingerprint == parsed.fingerprint else { return .refuse(.fingerprintMismatch) }
            return .restoreMarker(record.deviceIdentifier)
        } catch { return .refuse(.recordUnavailable) }
    }
}

// MARK: - The launcher's entry point

// Call before anything asks the launcher whether this iPad is enrolled.
// Idempotent, once per launch, main thread, and it never throws: the worst it
// can do is say why it did nothing.
@objc(WKEnrollmentReference)
public final class WKEnrollmentReference: NSObject {
    static let markerKey = "TKEnrolledDeviceIdentifier"

    @objc public static func prepare() -> String {
        let defaults = UserDefaults.standard
        let store: EnrollmentReferenceStore
        let keychain: PairingKeychain
        do {
            store = try EnrollmentReferenceStore()
            keychain = try PairingKeychain()
        } catch { return describe(.refuse(.storageUnavailable)) }
        let marker = defaults.string(forKey: markerKey)
        let reference: Data?
        do { reference = try store.read() }
        catch { return describe(.refuse(.storageUnavailable)) }

        let resolver = EnrollmentReferenceResolver(records: keychain)
        let decision = resolver.decide(marker: marker, reference: reference)
        switch decision {
        case .nothing, .current:
            break
        case .writeReference(let record):
            do { try store.write(try record.serialize()) }
            catch { return describe(.refuse(.storageUnavailable)) }
        case .restoreMarker(let identifier):
            // Re-check the identifier on the way out: the marker is what the
            // preflight reads, so nothing derived is written without the rule
            // that governs a written marker.
            guard EnrollmentReferenceRecord.validIdentifier(identifier) else { return describe(.refuse(.invalidMarker)) }
            defaults.set(identifier, forKey: markerKey)
        case .refuse(.staleReference), .refuse(.malformedReference):
            // Unusable by anyone from here on: remove it rather than leave a
            // record that would be refused again on every launch.
            try? store.clear()
        case .refuse:
            break
        }
        return describe(decision)
    }

    // One bounded line with a closed vocabulary. No identifier, no fingerprint,
    // no key and no path can travel in it.
    static func describe(_ decision: EnrollmentReferenceDecision) -> String {
        switch decision {
        case .nothing: return "event=reference outcome=nothing reason=no-marker-no-reference"
        case .current: return "event=reference outcome=current reason=reference-matches-record"
        case .writeReference: return "event=reference outcome=recorded reason=record-verified"
        case .restoreMarker: return "event=reference outcome=recovered reason=record-verified"
        case .refuse(let reason): return "event=reference outcome=refused reason=\(reason.rawValue)"
        }
    }
}
