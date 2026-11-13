#!/bin/bash
# The developer-service handoff, at the level a Mac can prove.
#
# Four things have to hold before the app may launch an unchanged executable:
# the pinned peer verifies, the managed TLS/CDTunnel transport carries an RSP
# stream, the discovered raw debugger answers a capability query, and only then
# does the preparation service accept the host's bound request - replying with a
# confirmed detach or refusing. Each of those has a synthetic counterpart here, so
# a regression fails a gate instead of waiting for a device.
#
# Nothing in this script touches a device, a pairing record, a key chain or a game
# file: the peers are local, the keys are public fixtures and the arenas are
# synthetic addresses no process maps.
set -euo pipefail
cd "$(dirname "$0")/../.."
. wolkaraforever/tools/env.sh
wolkaraforever/tools/prepare.sh
cd build/platform
mkdir -p build/emulation
# The C and Objective-C the Swift fixtures link against.
xcrun clang -std=c11 -Wall -Wextra -Werror -c authorization/Control/ArenaControl.c -o build/emulation/ArenaControl.o
xcrun clang -std=c11 -Wall -Wextra -Werror -c authorization/DebugWire.c -o build/emulation/DebugWire.o
xcrun clang -fobjc-arc -Wall -Wextra -Werror -Iauthorization/Pairing -c authorization/Pairing/TunnelTLS.m -o build/emulation/TunnelTLS.o
# Session: proof failure, cancellation before the peer answers, TLS failure, a
# startup deadline and a late result that must not restart anything.
xcrun swiftc -module-cache-path build/swift-module-cache -warnings-as-errors -g -sanitize=address \
    -import-objc-header authorization/Transport/TransportBridge.h \
    authorization/Pairing/*.swift authorization/Transport/*.swift authorization/Debugger/*.swift \
    build/emulation/ArenaControl.o build/emulation/DebugWire.o build/emulation/TunnelTLS.o \
    tests/test_developer_session.swift -o build/emulation/test_developer_session
build/emulation/test_developer_session
# The two probes the Python peer drives: the debug client on its own, and the
# preparation service that owns the one permitted attach.
for probe in probe_debug_over_tunnel probe_arena_service; do
    xcrun swiftc -module-cache-path build/swift-module-cache -warnings-as-errors -g -sanitize=address \
        -import-objc-header authorization/Transport/TransportBridge.h \
        authorization/Pairing/*.swift authorization/Transport/*.swift authorization/Debugger/*.swift \
        build/emulation/TunnelTLS.o build/emulation/DebugWire.o build/emulation/ArenaControl.o \
        tools/$probe.swift -o build/$probe
done
# Valid, wrong challenge (and its confirmed cleanup) and a lost detach reply, which
# must never read as success.
python3 tools/test_debug_over_tunnel.py
# The same through ArenaPreparationService: the unconfigured service rejects, a
# verified one prepares and detaches, a wrong challenge is refused, a lost detach
# reply leaves the arena uncertain, and an expired request is declined.
python3 tools/test_debug_over_tunnel.py --service
# The enrolment reference: the decision table, with the store and the record
# loader injected. A reinstall deletes the marker this app keeps in its own
# container and keeps the trust pin in the Keychain; recovering the one from the
# other must never replace a marker, overwrite a pin or restore trust that does
# not verify. The real-Keychain half of the same file is
# tools/test_enrollment_reference_sim.sh, which needs a simulator.
mkdir -p build/emulation
xcrun swiftc -module-cache-path build/swift-module-cache -warnings-as-errors -g -sanitize=address \
    authorization/Pairing/PairingWire.swift authorization/Pairing/PairingIdentity.swift \
    authorization/Storage/PairingEnrollment.swift authorization/Storage/PairingKeychain.swift \
    authorization/Storage/EnrollmentReference.swift tests/test_enrollment_reference.swift \
    -o build/emulation/test_enrollment_reference
build/emulation/test_enrollment_reference
