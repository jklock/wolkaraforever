#!/bin/bash
# The game's sound with and without iOS's HAL (patch 0065, WolkaraForeverAudioAvoidHAL), in the matrix simulator:
#   - the CoreAudio adapter's property API and the game's own HAL calls (tests/test_audio_hardware.m, the platform's
#     test with its host): switch on (the default) = answered by the model, 0 calls reach iOS's HAL; switch off = the
#     same answers from iOS's HAL;
#   - a 440 Hz test tone through the game's whole path (tests/test_audio_tone.m: HAL default output -> the HAL output
#     unit -> the AudioToolbox adapter's RemoteIO -> a render callback), both switch states: RemoteIO pulls about a
#     second of tone, and with the switch on neither adapter hands a call to iOS's HAL.
# A simulator, not the iPad: the simulator never loads HAL plug-ins into a process, so whether BTAudioHALPlugin is
# gone can only be seen in the game's process on an iPad.
#
#   wolkaraforever/tools/test_audio_sim.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
. wolkaraforever/tools/env.sh
. wolkaraforever/tools/simulators.sh
wolkaraforever/tools/prepare.sh
cd build/platform
# The matrix iPad, or the matrix iPhone with `SIMULATOR=iphone`; anything else is refused.
simulator_use "${SIMULATOR:-ipad}"
xcrun simctl bootstatus "$SIM_ID" -b > /dev/null
OUT=build/audio-fixture
mkdir -p "$OUT"
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
CC=(xcrun --sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -isysroot "$SDK" -fobjc-arc -O1 -g
    -Wall -Wextra -Werror -Wno-unused-parameter -Wno-deprecated-declarations -Itranslation/AKSupport)
OFF=(-WolkaraForeverAudioAvoidHAL '<false/>')

# shellcheck disable=SC2046 # the ldflags file is a list of flags
"${CC[@]}" translation/AKSupport/AKSupport.m translation/CoreAudio/*.m tests/test_audio_hardware.m \
    $(cat translation/CoreAudio/ldflags) -framework CoreAudio -o "$OUT/test_audio_hardware"
xcrun simctl spawn "$SIM_ID" "$PWD/$OUT/test_audio_hardware" 2>&1 | tee "$OUT/hardware-on.log"
grep -q "0 calls reached iOS's HAL: PASS" "$OUT/hardware-on.log"
grep -q '\[ak\] audio: HAL model answers the game' "$OUT/hardware-on.log"
if grep -q 'audio: HAL fallback' "$OUT/hardware-on.log"; then echo "a call fell back to iOS's HAL with the switch on" >&2; exit 1; fi
xcrun simctl spawn "$SIM_ID" "$PWD/$OUT/test_audio_hardware" "${OFF[@]}" 2>&1 | tee "$OUT/hardware-off.log"
grep -q "calls handed to iOS's HAL: PASS" "$OUT/hardware-off.log"
grep -q '\[ak\] audio: HAL in use (WolkaraForeverAudioAvoidHAL is off)' "$OUT/hardware-off.log"

# shellcheck disable=SC2046 # the ldflags file is a list of flags
"${CC[@]}" translation/AKSupport/AKSupport.m translation/CoreAudio/*.m translation/AudioToolbox/*.m \
    tests/test_audio_tone.m $(cat translation/CoreAudio/ldflags) -framework CoreAudio -framework AudioToolbox \
    -o "$OUT/test_audio_tone"
xcrun simctl spawn "$SIM_ID" "$PWD/$OUT/test_audio_tone" 2>&1 | tee "$OUT/tone-on.log"
grep -q "0 calls reached iOS's HAL: PASS" "$OUT/tone-on.log"
grep -q '\[ak\] audio: HAL avoided (RemoteIO)' "$OUT/tone-on.log"
xcrun simctl spawn "$SIM_ID" "$PWD/$OUT/test_audio_tone" "${OFF[@]}" 2>&1 | tee "$OUT/tone-off.log"
grep -q "calls handed to iOS's HAL: PASS" "$OUT/tone-off.log"
grep -q '\[ak\] audio: HAL in use (WolkaraForeverAudioAvoidHAL is off)' "$OUT/tone-off.log"
echo "AUDIO_SIM_PASS: the game's HAL calls and a test tone, with the HAL avoided (0 calls to iOS's HAL) and with it in use"
