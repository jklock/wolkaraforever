import Foundation
import CryptoKit
import Security

// The enrolment reference's whole decision table, with no Keychain and no device.
//
// The store and the record loader are the only two things this code talks to, so
// they are what the test replaces. Every branch the app can take is a value, and
// every value is checked here: matching, backfilled, repaired, recovered, stale,
// mismatching, malformed, invalid marker, an unreadable record, and the rule that
// a marker which exists is never replaced.
@main struct EnrollmentReferenceTests {
    static let device = "synthetic-enrollment-reference-device"
    static let other = "synthetic-enrollment-reference-other"

    final class Backend: PairingKeychainBackend {
        var items: [String: [String: Any]] = [:]
        var additions = 0
        func add(_ attributes: [String: Any]) -> OSStatus {
            guard let account = attributes[kSecAttrAccount as String] as? String else { return errSecParam }
            if items[account] != nil { return errSecDuplicateItem }
            additions += 1
            items[account] = attributes
            return errSecSuccess
        }
        func copy(_ query: [String: Any]) -> (OSStatus, Any?) {
            guard let account = query[kSecAttrAccount as String] as? String else { return (errSecParam, nil) }
            guard let item = items[account] else { return (errSecItemNotFound, nil) }
            return (errSecSuccess, item)
        }
        func delete(_ query: [String: Any]) -> OSStatus {
            guard let account = query[kSecAttrAccount as String] as? String else { return errSecParam }
            return items.removeValue(forKey: account) != nil ? errSecSuccess : errSecItemNotFound
        }
    }

    final class Records: EnrollmentReferenceRecords {
        var byIdentifier: [String: PairingEnrollment] = [:]
        var failure: Error?
        func record(deviceIdentifier: String) throws -> PairingEnrollment? {
            if let failure = failure { throw failure }
            return byIdentifier[deviceIdentifier]
        }
    }

    // Deterministic fixture keys. Never used for enrolment.
    static func record(_ identifier: String, peer: UInt8 = 0x32) throws -> PairingEnrollment {
        let host = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(repeating: 0x21, count: 32))
        let peerKey = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(repeating: peer, count: 32))
        let identity = try PairingIdentity(hostIdentifier: Data("synthetic-host".utf8),
            privateKey: host.rawRepresentation, publicKey: host.publicKey.rawRepresentation,
            peerIdentifier: Data("synthetic-peer".utf8), peerPublicKey: peerKey.publicKey.rawRepresentation)
        return try PairingEnrollment(identity: identity, deviceIdentifier: identifier,
            connectionIdentifier: UUID(uuidString: "00112233-4455-6677-8899-aabbccddeeff")!)
    }

    static func reference(_ identifier: String, peer: UInt8 = 0x32) throws -> Data {
        let record = try record(identifier, peer: peer)
        return try EnrollmentReferenceRecord(deviceIdentifier: identifier, fingerprint: record.fingerprint).serialize()
    }

    static func store(_ backend: Backend) throws -> EnrollmentReferenceStore {
        try EnrollmentReferenceStore(accessGroup: "org.tolkara.tests.reference", backend: backend)
    }

    static func main() throws {
        try StoreRoundTrip()
        try DecisionTable()
        try ClosedLogVocabulary()
        print("Enrolment reference PASS: matching, backfilled, repaired, recovered, stale, mismatching, "
            + "malformed, oversized, invalid marker, unreadable record, never-replaced marker and the "
            + "one-item store all behave as required; no decision line carries pairing material.")
    }

    // The reference is one item under one fixed account, replaced rather than
    // accumulated, and unreadable when it comes back with different protection.
    static func StoreRoundTrip() throws {
        let backend = Backend()
        let store = try store(backend)
        let absent = try store.read()
        precondition(absent == nil, "an absent reference must read as absent, not as an error")
        let data = try reference(device)
        try store.write(data)
        let written = try store.read()
        precondition(written == data, "the written reference must read back byte for byte")
        precondition(EnrollmentReferenceStore.account == "enrollment-reference")
        try store.write(data)
        precondition(backend.items.count == 1 && backend.additions == 2, "the reference must be replaced, never accumulated")
        try store.clear()
        let cleared = try store.read()
        precondition(cleared == nil)
        try store.clear()  // idempotent
        // A reference that returns with another protection class is not ours.
        try store.write(data)
        var item = backend.items[EnrollmentReferenceStore.account]!
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock as String
        backend.items[EnrollmentReferenceStore.account] = item
        do { _ = try store.read(); precondition(false, "another protection class was accepted") }
        catch EnrollmentReferenceFailure.corruptRecord {}
        // A group that is not a group is refused before anything is stored.
        do { _ = try EnrollmentReferenceStore(accessGroup: "not-a-group", backend: backend); precondition(false) }
        catch EnrollmentReferenceFailure.configuration {}
    }

    static func DecisionTable() throws {
        let a = try record(device), b = try record(other, peer: 0x44)
        let records = Records()
        records.byIdentifier[device] = a
        records.byIdentifier[other] = b
        let resolver = EnrollmentReferenceResolver(records: records)
        let wanted = try EnrollmentReferenceRecord(deviceIdentifier: device, fingerprint: a.fingerprint)
        let otherWanted = try EnrollmentReferenceRecord(deviceIdentifier: other, fingerprint: b.fingerprint)
        let deviceReference = try reference(device)
        let otherReference = try reference(other, peer: 0x44)
        let editedReference = try EnrollmentReferenceRecord(deviceIdentifier: device, fingerprint: Data(repeating: 0x00, count: 32)).serialize()
        let invalidMarker = String(repeating: "x", count: 1025)

        // First launch of an enrolled app: the reference is derived from the
        // record the marker names.
        precondition(resolver.decide(marker: device, reference: nil) == .writeReference(wanted))
        // The launch after that: nothing to do.
        precondition(resolver.decide(marker: device, reference: deviceReference) == .current)
        // A reference left over from another device, or a damaged one, is
        // repaired from the record - the marker is the authority while it exists.
        precondition(resolver.decide(marker: device, reference: otherReference) == .writeReference(wanted))
        precondition(resolver.decide(marker: device, reference: Data()) == .writeReference(wanted))

        // Reinstall: the marker is gone, the record is not, and the reference
        // names it. This is the whole point of the file.
        precondition(resolver.decide(marker: nil, reference: deviceReference) == .restoreMarker(device))
        precondition(resolver.decide(marker: "", reference: deviceReference) == .restoreMarker(device))

        // Stale: the reference outlived the record it names. Never restore it.
        let staleRecords = Records()
        staleRecords.byIdentifier[other] = b
        let stale = EnrollmentReferenceResolver(records: staleRecords)
        precondition(stale.decide(marker: nil, reference: deviceReference) == .refuse(.staleReference))
        // Mismatching: a record with that identifier exists, but it is not the
        // one the reference was derived from. Never overwrite it.
        precondition(resolver.decide(marker: nil, reference: editedReference) == .refuse(.fingerprintMismatch))
        // Malformed and oversized references are refused, not parsed loosely.
        precondition(resolver.decide(marker: nil, reference: Data("not a reference".utf8)) == .refuse(.malformedReference))
        precondition(resolver.decide(marker: nil, reference: Data(repeating: 0x7f, count: EnrollmentReferenceRecord.maximumSize + 1)) == .refuse(.malformedReference))

        // Nothing on either side: an app that never enrolled.
        precondition(resolver.decide(marker: nil, reference: nil) == .nothing)

        // A marker that exists is never replaced, whatever the reference says:
        // the decision is about that marker's own record.
        precondition(resolver.decide(marker: device, reference: otherReference) != .restoreMarker(other))
        precondition(resolver.decide(marker: other, reference: deviceReference) == .writeReference(otherWanted))
        // A marker that is not an identifier cannot be restored over and cannot
        // be made into a reference.
        precondition(resolver.decide(marker: invalidMarker, reference: deviceReference) == .refuse(.invalidMarker))
        precondition(resolver.decide(marker: "identifier\u{0}with-a-control", reference: nil) == .refuse(.invalidMarker))

        // A record that will not load is not silently re-derived or replaced.
        let broken = Records()
        broken.byIdentifier[device] = a
        broken.failure = PairingKeychain.Failure.corruptRecord
        precondition(EnrollmentReferenceResolver(records: broken).decide(marker: device, reference: nil) == .refuse(.recordUnavailable))
        precondition(EnrollmentReferenceResolver(records: broken).decide(marker: nil, reference: deviceReference) == .refuse(.recordUnavailable))
    }

    // The line the app logs is a closed vocabulary: no identifier, no
    // fingerprint, no path and nothing that could carry one.
    static func ClosedLogVocabulary() throws {
        let record = try EnrollmentReferenceRecord(deviceIdentifier: device, fingerprint: Data(repeating: 0x11, count: 32))
        let decisions: [EnrollmentReferenceDecision] = [.nothing, .current,
            .writeReference(record),
            .restoreMarker(device),
            .refuse(.invalidMarker), .refuse(.recordUnavailable), .refuse(.staleReference),
            .refuse(.fingerprintMismatch), .refuse(.malformedReference), .refuse(.storageUnavailable)]
        for decision in decisions {
            let line = WKEnrollmentReference.describe(decision)
            precondition(line.hasPrefix("event=reference outcome="), line)
            precondition(!line.contains(device) && !line.contains("synthetic"), line)
            precondition(!line.contains(String(repeating: "1", count: 64)), line)
            precondition(line.utf8.count < 96, "a log line has to stay bounded: \(line.count) bytes")
            let keys = line.split(separator: " ").map { $0.split(separator: "=").first.map(String.init) ?? "" }
            precondition(keys.allSatisfy { ["event", "outcome", "reason"].contains($0) }, line)
        }
    }
}
