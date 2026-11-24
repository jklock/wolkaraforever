# The simulator half of the test matrix. Sourced by the layer's tools.
#
# This project tests on three devices and no others:
#
#   1. iPhone Duo                    - simulator
#   2. iPad Pro 13-inch (M5)         - simulator
#   3. iPad Pro 12.9-inch (5th gen)  - the physical iPad, through device_matrix.sh
#
# There is no "next best device". A suite that cannot find its matrix device
# fails and says so, instead of quietly measuring a device nobody chose; and
# nothing here creates a simulator, so a missing device is a setup problem to
# report, not something to paper over.
#
# `simulator_udid [ipad|iphone|<name>|<udid>]` prints the UDID of that matrix
# device, preferring an instance that is already booted. Anything off the matrix
# is refused with exit 2, including a name or UDID passed in SIMULATOR.
# `simulator_name <udid>` prints the display name, for the log line that says
# which device actually ran.

# The names Xcode gives them, as prefixes: Xcode appends details such as
# "(16GB)" to some device names, and that suffix is not ours to depend on.
WOLKARA_MATRIX_IPAD="iPad Pro 13-inch (M5)"
WOLKARA_MATRIX_IPHONE="iPhone Duo"
WOLKARA_MATRIX_PHYSICAL="iPad Pro 12.9-inch (5th generation)"

simulator_udid() {
    local wanted=${1:-ipad}
    # `-c`, not `-`: the program arrives on the command line so that stdin stays
    # free for simctl's JSON.
    xcrun simctl list devices available -j | python3 -c '
import json, sys

# Lower-case name prefixes, so "(16GB)" and any other suffix still matches.
MATRIX = {"ipad": "ipad pro 13-inch (m5)", "iphone": "iphone duo"}
LABELS = {"ipad": "iPad Pro 13-inch (M5)", "iphone": "iPhone Duo"}

wanted = sys.argv[1].strip()
devices = [d for group in json.load(sys.stdin)["devices"].values() for d in group]


def on_matrix(name):
    return any(name.lower().startswith(prefix) for prefix in MATRIX.values())


if wanted.lower() in MATRIX:
    prefix = MATRIX[wanted.lower()]
    found = [d for d in devices if d["name"].lower().startswith(prefix)]
    missing = "no %s simulator on this machine" % LABELS[wanted.lower()]
elif wanted:
    # A name matches the same way the matrix keys do - by prefix - so the
    # "(16GB)" Xcode appends to some device names does not turn a matrix device
    # into an unrecognised one.
    found = [
        d for d in devices
        if on_matrix(d["name"]) and (d["udid"] == wanted or d["name"].lower().startswith(wanted.lower()))
    ]
    missing = "%s is not on the test matrix" % wanted
else:
    found, missing = [], "no device was asked for"

if not found:
    sys.stderr.write(
        "%s. Tests run on iPad Pro 13-inch (M5) and iPhone Duo in the simulator, "
        "and on the iPad Pro 12.9-inch (5th generation) on hardware; nothing else.\n" % missing
    )
    raise SystemExit(2)

found.sort(key=lambda d: d["state"] != "Booted")
print(found[0]["udid"])' "$wanted"
}

simulator_name() {
    xcrun simctl list devices -j | python3 -c '
import json, sys
for group in json.load(sys.stdin)["devices"].values():
    for device in group:
        if device["udid"] == sys.argv[1]:
            print(device["name"])
            raise SystemExit
print(sys.argv[1])' "$1"
}

# Resolve SIMULATOR (or the matrix default) once, print the device, and export
# the UDID as SIMULATOR so a script that shells out to the platform's own tools
# hands them the same device.
simulator_use() {
    local wanted=${1:-${SIMULATOR:-ipad}}
    SIM_ID=$(simulator_udid "$wanted") || exit 2
    SIMULATOR=$SIM_ID
    export SIMULATOR
    SIM_NAME=$(simulator_name "$SIM_ID")
    printf '%s: %s (%s)\n' "$(basename "${BASH_SOURCE[1]:-script}" .sh)" "$SIM_NAME" "$SIM_ID" >&2
}

# For a fresh machine with nothing booted, such as a hosted CI runner: a first boot takes minutes,
# so the Validate workflow starts it early, in the background, and each suite still waits for its
# simulator to finish booting. Not for a Mac someone is using: it boots a device, which on a
# person's Mac is their decision.
#
# simulator_start_boot [ipad|iphone]   starts booting that matrix simulator and returns at once.
simulator_start_boot() {
    simulator_use "${1:-${SIMULATOR:-ipad}}"
    nohup xcrun simctl boot "$SIM_ID" > /dev/null 2>&1 &
}

# simulator_app_documents <bundle id> [ipad|iphone]   prints that app's Documents folder on the
# matrix simulator, where the fixtures leave the pictures they drew.
simulator_app_documents() {
    local udid
    udid=$(simulator_udid "${2:-${SIMULATOR:-ipad}}") || return 2
    printf '%s/Documents\n' "$(xcrun simctl get_app_container "$udid" "$1" data 2>/dev/null)"
}

# One UI suite per simulator, enforced. Two suites on the same device install over each other's
# app, take the foreground from each other and interleave their sheets; whatever runs second then
# reports failures it does not have. Measured twice: on 2026-11-13 a touch-controls suite launched
# on the iPad while the launcher suite was mid-run and its fixture was pulled out from under it,
# and on 2026-11-16 a touch suite's window was in front when the launcher suite drew one baseline,
# which moved 908 pixels of it. Refusing to start is honest; a bogus red lane is not.
#
# simulator_ui_lock <owner>   takes it or exits 3. Released on exit; a lock whose owner is gone is
# taken over, so a killed run cannot wedge the device for every run after it.
simulator_ui_lock() {
    local owner=${1:-$(basename "${BASH_SOURCE[1]:-suite}" .sh)}
    # A global, because the trap that releases it runs after this function has returned: a local
    # name is out of scope by then and the release failed with "unbound variable".
    SIM_UI_LOCK="${TMPDIR:-/tmp}/wolkaraforever-ui-${SIM_ID}.lock"
    if ! mkdir "$SIM_UI_LOCK" 2>/dev/null; then
        local holder
        holder=$(cat "$SIM_UI_LOCK/pid" 2>/dev/null || true)
        if [ -n "$holder" ] && ! kill -0 "$holder" 2>/dev/null; then
            echo "$owner: taking over a stale UI lock (pid $holder is gone)" >&2
            rm -rf "$SIM_UI_LOCK"
            mkdir "$SIM_UI_LOCK" 2>/dev/null || { echo "$owner: cannot take $SIM_UI_LOCK" >&2; exit 3; }
        else
            echo "$owner: another UI suite is using $SIM_NAME ($SIM_UI_LOCK${holder:+, pid $holder})" >&2
            echo "$owner: remove the lock only if no suite is running" >&2
            exit 3
        fi
    fi
    printf '%s\n' "$$" > "$SIM_UI_LOCK/pid"
    trap 'rm -rf "$SIM_UI_LOCK"' EXIT INT TERM
}
