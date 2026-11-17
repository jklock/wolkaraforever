// The CoreAudio adapter's property API as Wine's Mac audio driver uses it: the
// session's route, reported under the legacy default output's ID.
//
// This is the platform's test with the host it now needs. Patch 0005 stopped the
// adapter taking the audio session for itself - it asks the app for the game's
// playback lease instead, through dlsym, because the adapter is its own image and
// cannot link against the app's symbol. A plain `simctl spawn` has no app, so the
// platform's version of this test asks for nothing, gets no route, and aborts at
// its first assertion; the rest of the adapter suite then never runs.
//
// So this file takes the lease the way the app does. Everything the adapter must
// answer is asserted exactly as the platform asserts it - the test is not weakened,
// its missing host is supplied.
//
// Patch 0065 (the game's sound without iOS's HAL): with WolkaraForeverAudioAvoidHAL on (the default) the adapter
// answers from its model of one output device and NOTHING reaches iOS's HAL - the calls the game makes (its exact
// sequence from the iPad's log of 18 Nov 2026) and the property API above alike; TKCoreAudioHALForwards() counts every
// call the adapter hands to iOS. Spawned with `-WolkaraForeverAudioAvoidHAL '<false/>'` it is the old path: the same
// answers, from iOS's HAL (forwards > 0), so the counter is shown to measure.
//
// Run in the simulator (tools/test_translation_sim.sh; both switch states: wolkaraforever/tools/test_audio_sim.sh).
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreAudioTypes/CoreAudioTypes.h>
#import "AKAudioModel.h"
#include <assert.h>
typedef struct { UInt32 mSelector, mScope, mElement; } Address;
typedef OSStatus (*HardwareListener)(UInt32, void *);
typedef OSStatus (*ObjectListener)(UInt32, UInt32, const Address *, void *);
typedef void (^ObjectListenerBlock)(UInt32, const Address *);
extern OSStatus AudioObjectGetPropertyDataSize(UInt32, const Address *, UInt32, const void *, UInt32 *);
extern OSStatus AudioObjectGetPropertyData(UInt32, const Address *, UInt32, const void *, UInt32 *, void *);
extern OSStatus AudioObjectSetPropertyData(UInt32, const Address *, UInt32, const void *, UInt32, const void *);
extern Boolean AudioObjectHasProperty(UInt32, const Address *);
extern OSStatus AudioObjectAddPropertyListener(UInt32, const Address *, ObjectListener, void *);
extern OSStatus AudioObjectRemovePropertyListener(UInt32, const Address *, ObjectListener, void *);
extern OSStatus AudioObjectAddPropertyListenerBlock(UInt32, const Address *, dispatch_queue_t, ObjectListenerBlock);
extern OSStatus AudioObjectRemovePropertyListenerBlock(UInt32, const Address *, dispatch_queue_t, ObjectListenerBlock);
extern OSStatus AudioHardwareGetProperty(UInt32, UInt32 *, void *);
extern OSStatus AudioHardwareGetPropertyInfo(UInt32, UInt32 *, Boolean *);
extern OSStatus AudioHardwareAddPropertyListener(UInt32, HardwareListener, void *);
extern OSStatus AudioHardwareRemovePropertyListener(UInt32, HardwareListener);
extern OSStatus AudioDeviceGetPropertyInfo(UInt32, UInt32, Boolean, UInt32, UInt32 *, Boolean *);
extern OSStatus AudioDeviceGetProperty(UInt32, UInt32, Boolean, UInt32, UInt32 *, void *);
extern OSStatus AudioDeviceAddPropertyListener(UInt32, UInt32, Boolean, UInt32, void *, void *);
extern OSStatus AudioDeviceRemovePropertyListener(UInt32, UInt32, Boolean, UInt32, void *);
extern unsigned TKCoreAudioHALForwards(void);

// The host half of patch 0005's contract. Exported, so the adapter's
// dlsym(RTLD_DEFAULT, "TKWolkaraForeverRequestGamePlayback") finds it.
BOOL TKWolkaraForeverRequestGamePlayback(void) {
    AVAudioSession *session = AVAudioSession.sharedInstance;
    NSError *error = nil;
    if ([session.category isEqualToString:AVAudioSessionCategoryPlayAndRecord])
        return [session setActive:YES error:&error];
    if (![session setCategory:AVAudioSessionCategoryPlayback error:&error]) return NO;
    return [session setActive:YES error:&error];
}

static OSStatus hardwareChanged(UInt32 property, void *context) { return 0; }
static OSStatus objectChanged(UInt32 object, UInt32 count, const Address *addresses, void *context) { return 0; }

// The game's own calls, in the order the iPad's log shows them (native-guest.log, 18 Nov 01:03:14): listeners on
// the default output, the default input and the device list; the default output and its name; the default input
// and its name; the device list's size; the output's preferred channel layout ('srnd', 52 bytes = stereo), rate
// and IO buffer size. Returns the default output.
static UInt32 the_games_calls(void) {
    assert(!AudioHardwareAddPropertyListener('dOut', hardwareChanged, NULL));
    assert(!AudioHardwareAddPropertyListener('dIn ', hardwareChanged, NULL));
    assert(!AudioHardwareAddPropertyListener('dev#', hardwareChanged, NULL));
    UInt32 output = 0, input = 0, size = sizeof output;
    assert(!AudioHardwareGetProperty('dOut', &size, &output) && output && size == sizeof output);
    char name[256] = {0}; size = sizeof name;
    assert(!AudioDeviceGetProperty(output, 0, false, 'name', &size, name) && size > 1 && strlen(name) == size - 1);
    size = sizeof input;
    assert(!AudioHardwareGetProperty('dIn ', &size, &input) && size == sizeof input);
    if (input) { size = sizeof name; assert(!AudioDeviceGetProperty(input, 0, false, 'name', &size, name) && size > 1); }
    Boolean writable = true;
    size = 99; assert(!AudioHardwareGetPropertyInfo('dev#', &size, &writable));
    UInt32 layoutSize = 0;
    assert(!AudioDeviceGetPropertyInfo(output, 0, false, 'srnd', &layoutSize, &writable) && layoutSize >= 12);
    union { AudioChannelLayout layout; char bytes[512]; } layout = {0};
    size = sizeof layout;
    assert(!AudioDeviceGetProperty(output, 0, false, 'srnd', &size, &layout) && size == layoutSize);
    Float64 rate = 0; size = sizeof rate;
    assert(!AudioDeviceGetProperty(output, 0, false, 'nsrt', &size, &rate) && rate > 0);
    UInt32 frames = 0; size = sizeof frames;
    assert(!AudioDeviceGetProperty(output, 0, false, 'fsz#', &size, &frames) && frames > 0);
    return output;
}

int main(void) { @autoreleasepool {
    BOOL avoid = AKAudioAvoidHALIn(NSUserDefaults.standardUserDefaults);
    // A duplex host still has a real output route. The adapter must not disappear
    // the game device merely because dictation has enabled microphone input.
    AVAudioSession *session = AVAudioSession.sharedInstance;
    assert([session setCategory:AVAudioSessionCategoryPlayAndRecord
                           mode:AVAudioSessionModeDefault
                        options:AVAudioSessionCategoryOptionMixWithOthers error:NULL]);
    assert(TKWolkaraForeverRequestGamePlayback());
    UInt32 game = the_games_calls();
    if (avoid) {
        assert(game == AKAudioModelDevice);
        // The model's answers: the input is the same device (iOS's HAL said so on the iPad), the legacy device list is
        // empty (as iOS's was: size 0), the layout is stereo left/right in 52 bytes (as iOS's was).
        UInt32 input = 0, size = sizeof input;
        assert(!AudioHardwareGetProperty('dIn ', &size, &input) && input == AKAudioModelDevice);
        Boolean writable = true; size = 99;
        assert(!AudioHardwareGetPropertyInfo('dev#', &size, &writable) && size == 0);
        union { AudioChannelLayout layout; char bytes[512]; } layout = {0}; size = sizeof layout;
        assert(!AudioDeviceGetProperty(game, 0, false, 'srnd', &size, &layout) && size == 52);
        assert(layout.layout.mChannelLayoutTag == kAudioChannelLayoutTag_UseChannelDescriptions);
        assert(layout.layout.mNumberChannelDescriptions == 2);
        assert(layout.layout.mChannelDescriptions[0].mChannelLabel == kAudioChannelLabel_Left);
        assert(layout.layout.mChannelDescriptions[1].mChannelLabel == kAudioChannelLabel_Right);
        char name[256] = {0}; size = sizeof name;
        assert(!AudioDeviceGetProperty(game, 0, false, 'name', &size, name));
        assert([@(name) isEqualToString:[(AVAudioSessionPortDescription *)session.currentRoute.outputs.firstObject portName]]);
        size = 3; assert(AudioDeviceGetProperty(game, 0, false, 'name', &size, name) == '!siz');
        Float64 rate = 0; size = sizeof rate;
        assert(!AudioDeviceGetProperty(game, 0, false, 'nsrt', &size, &rate) && rate == session.sampleRate);
    }
    UInt32 legacy = 0, size = sizeof legacy;
    assert(!AudioHardwareGetProperty('dOut', &size, &legacy) && legacy);
    assert(avoid ? legacy == AKAudioModelDevice : legacy != AKAudioModelDevice);
    Address devices = {'dev#', 'glob', 0}, fallback = {'dOut', 'glob', 0};
    UInt32 device = 0; size = 0;
    assert(!AudioObjectGetPropertyDataSize(1, &devices, 0, NULL, &size) && size == sizeof device);
    assert(!AudioObjectGetPropertyData(1, &devices, 0, NULL, &size, &device) && device == legacy);
    size = sizeof device; device = 0;
    assert(!AudioObjectGetPropertyData(1, &fallback, 0, NULL, &size, &device) && device == legacy);
    // Output channels, and no input on the output device.
    Address output = {'slay', 'outp', 0}, input = {'slay', 'inpt', 0};
    union { AudioBufferList list; char bytes[64]; } buffers;
    assert(!AudioObjectGetPropertyDataSize(device, &output, 0, NULL, &size) && size <= sizeof buffers);
    assert(!AudioObjectGetPropertyData(device, &output, 0, NULL, &size, &buffers) && buffers.list.mNumberBuffers == 1 && buffers.list.mBuffers[0].mNumberChannels >= 1);
    size = sizeof buffers;
    assert(!AudioObjectGetPropertyData(device, &input, 0, NULL, &size, &buffers) && buffers.list.mNumberBuffers == 0);
    // Name, UID and back, rate, streams, latency; a too small buffer is refused.
    Address name = {'lnam', 'outp', 0}, uid = {'uid ', 'outp', 0}, rate = {'nsrt', 'outp', 0};
    Address streams = {'stm#', 'outp', 0}, latency = {'ltnc', 'outp', 0}, translate = {'uidd', 'glob', 0};
    CFStringRef text = NULL; size = sizeof text;
    assert(!AudioObjectGetPropertyData(device, &name, 0, NULL, &size, &text) && text && CFStringGetLength(text)); CFRelease(text);
    size = sizeof text;
    assert(!AudioObjectGetPropertyData(device, &uid, 0, NULL, &size, &text) && [(__bridge NSString *)text isEqualToString:@"TolkaraOutput"]);
    UInt32 found = 0; size = sizeof found;
    assert(!AudioObjectGetPropertyData(1, &translate, sizeof text, &text, &size, &found) && found == device); CFRelease(text);
    Float64 hz = 0; size = sizeof hz;
    assert(!AudioObjectGetPropertyData(device, &rate, 0, NULL, &size, &hz) && hz > 0);
    size = 99; assert(!AudioObjectGetPropertyDataSize(device, &streams, 0, NULL, &size) && size == 0);
    UInt32 frames = 0; size = sizeof frames; assert(!AudioObjectGetPropertyData(device, &latency, 0, NULL, &size, &frames));
    size = 2; assert(AudioObjectGetPropertyData(device, &rate, 0, NULL, &size, &hz) == '!siz');
    // The user's volume is left alone.
    Address volume = {'volm', 'glob', 0}; Float32 level = 0.25f;
    assert(!AudioObjectSetPropertyData(device, &volume, 0, NULL, sizeof level, &level));
    puts("audio property API: one output device from the session's route, name, UID, rate, streams, latency and volume: PASS");
    if (avoid) {
        // Listeners of every kind are taken without iOS (the model's device never changes: RemoteIO follows the
        // route itself), and what the model has is said to be there.
        Address defaultOutput = {'dOut', 'glob', 0};
        assert(AudioObjectHasProperty(1, &defaultOutput) && AudioObjectHasProperty(device, &rate));
        assert(!AudioObjectAddPropertyListener(1, &defaultOutput, objectChanged, NULL));
        assert(!AudioObjectRemovePropertyListener(1, &defaultOutput, objectChanged, NULL));
        ObjectListenerBlock block = ^(UInt32 count, const Address *addresses) {};
        assert(!AudioObjectAddPropertyListenerBlock(1, &defaultOutput, dispatch_get_main_queue(), block));
        assert(!AudioObjectRemovePropertyListenerBlock(1, &defaultOutput, dispatch_get_main_queue(), block));
        assert(!AudioDeviceAddPropertyListener(device, 0, false, 'nsrt', NULL, NULL));
        assert(!AudioDeviceRemovePropertyListener(device, 0, false, 'nsrt', NULL));
        assert(!AudioHardwareRemovePropertyListener('dOut', hardwareChanged));
        assert(TKCoreAudioHALForwards() == 0);
        puts("audio without iOS's HAL: the game's calls and the property API answered by the model, 0 calls reached iOS's HAL: PASS");
    } else {
        assert(TKCoreAudioHALForwards() > 0);
        printf("audio with iOS's HAL (switch off): the same answers, %u calls handed to iOS's HAL: PASS\n", TKCoreAudioHALForwards());
    }
} }
