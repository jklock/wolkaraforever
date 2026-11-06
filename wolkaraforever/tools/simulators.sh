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
