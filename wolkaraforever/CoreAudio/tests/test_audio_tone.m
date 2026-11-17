// A test tone through the game's whole sound path, with and without iOS's HAL (patch 0065).
//
// The game (FMOD in the macOS client) asks the HAL for the default output, then opens the HAL output unit
// ('auou'/'ahal'), points it at that device (kAudioOutputUnitProperty_CurrentDevice), sets a 48 kHz float stereo
// format and a render callback, and starts it. The AudioToolbox adapter maps the unit to RemoteIO. This test makes
// those calls - against the real CoreAudio and AudioToolbox adapters, linked in - with a 440 Hz sine as the render
// callback, runs it for a second, and checks RemoteIO pulled the tone: the callback ran, about a second of frames,
// none of them silent. With WolkaraForeverAudioAvoidHAL on (the default) neither adapter may hand a single call to
// iOS's HAL (TKCoreAudioHALForwards, TKAudioToolboxHALForwards); with it off (`-WolkaraForeverAudioAvoidHAL
// '<false/>'`) the same tone plays the old way, through iOS's HAL.
//
// The simulator never loads HAL plug-ins in-process (its HAL is the Mac's coreaudiod), so the plug-in list is only
// printed here, as a note; whether they are gone can only be seen in the game's process on an iPad.
//
// Run in the simulator: wolkaraforever/tools/test_audio_sim.sh.
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import "AKAudioModel.h"
#include <assert.h>
#include <math.h>
#include <mach-o/dyld.h>
#include <stdatomic.h>
extern OSStatus AudioHardwareGetProperty(UInt32, UInt32 *, void *);
extern OSStatus AudioHardwareAddPropertyListener(UInt32, OSStatus (*)(UInt32, void *), void *);
extern OSStatus AudioDeviceGetProperty(UInt32, UInt32, Boolean, UInt32, UInt32 *, void *);
extern unsigned TKCoreAudioHALForwards(void);
extern unsigned TKAudioToolboxHALForwards(void);

// The host half of patch 0005's contract (the app's coordinator, in the app).
BOOL TKWolkaraForeverRequestGamePlayback(void) {
    AVAudioSession *session = AVAudioSession.sharedInstance;
    NSError *error = nil;
    if (![session.category isEqualToString:AVAudioSessionCategoryPlayback] &&
        ![session setCategory:AVAudioSessionCategoryPlayback error:&error]) return NO;
    return [session setActive:YES error:&error];
}

static OSStatus changed(UInt32 property, void *context) { return 0; }

typedef struct { double phase, step; atomic_uint_fast64_t calls, frames, loud; } Tone;
static OSStatus render(void *context, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *time, UInt32 bus,
                       UInt32 frames, AudioBufferList *buffers) {
    Tone *tone = context;
    float *samples = buffers->mBuffers[0].mData;
    uint64_t loud = 0;
    for (UInt32 i = 0; i < frames; i++) {
        float value = (float)(0.05 * sin(tone->phase));
        tone->phase += tone->step;
        samples[2 * i] = samples[2 * i + 1] = value;
        if (fabsf(value) > 0.01f) loud++;
    }
    atomic_fetch_add(&tone->calls, 1);
    atomic_fetch_add(&tone->frames, frames);
    atomic_fetch_add(&tone->loud, loud);
    return 0;
}

static NSString *audioPlugIns(void) {
    NSMutableArray *names = [NSMutableArray new];
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        NSString *path = @(_dyld_get_image_name(i));
        if ([path containsString:@"/Audio/Plug-Ins/"]) [names addObject:path.lastPathComponent];
    }
    return names.count ? [names componentsJoinedByString:@", "] : @"none";
}

int main(void) { @autoreleasepool {
    BOOL avoid = AKAudioAvoidHALIn(NSUserDefaults.standardUserDefaults);
    assert(!AudioHardwareAddPropertyListener('dOut', changed, NULL));
    UInt32 device = 0, size = sizeof device;
    assert(!AudioHardwareGetProperty('dOut', &size, &device) && device);
    assert(avoid == (device == AKAudioModelDevice));
    Float64 rate = 0; size = sizeof rate;
    assert(!AudioDeviceGetProperty(device, 0, false, 'nsrt', &size, &rate) && rate > 0);

    AudioComponentDescription halOutput = {kAudioUnitType_Output, 'ahal', kAudioUnitManufacturer_Apple, 0, 0};
    AudioComponent component = AudioComponentFindNext(NULL, &halOutput);
    assert(component);
    AudioUnit unit = NULL;
    assert(!AudioComponentInstanceNew(component, &unit) && unit);
    UInt32 on = 1, off = 0;
    assert(!AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &on, sizeof on));
    assert(!AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &off, sizeof off));
    // The game's device - the model's under the switch - is the one RemoteIO takes; any other is refused.
    assert(!AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &device, sizeof device));
    UInt32 other = device + 1;
    assert(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &other, sizeof other));
    UInt32 current = 0; size = sizeof current;
    assert(!AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &current, &size) && current == device);
    AudioStreamBasicDescription format = {.mSampleRate = 48000, .mFormatID = kAudioFormatLinearPCM,
        .mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, .mBytesPerPacket = 8, .mFramesPerPacket = 1,
        .mBytesPerFrame = 8, .mChannelsPerFrame = 2, .mBitsPerChannel = 32};
    assert(!AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &format, sizeof format));
    static Tone tone;
    tone.step = 2 * M_PI * 440 / format.mSampleRate;
    AURenderCallbackStruct callback = {render, &tone};
    assert(!AudioUnitSetProperty(unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &callback, sizeof callback));
    assert(!AudioUnitInitialize(unit));
    assert(!AudioOutputUnitStart(unit));
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
    AudioOutputUnitStop(unit);
    AudioUnitUninitialize(unit);
    AudioComponentInstanceDispose(unit);
    uint64_t calls = atomic_load(&tone.calls), frames = atomic_load(&tone.frames), loud = atomic_load(&tone.loud);
    printf("tone: %llu render calls, %llu frames (%.2f s), %llu above the floor\n", (unsigned long long)calls,
           (unsigned long long)frames, frames / format.mSampleRate, (unsigned long long)loud);
    assert(calls > 10 && frames > 0.5 * format.mSampleRate && loud > frames / 2);
    unsigned forwards = TKCoreAudioHALForwards() + TKAudioToolboxHALForwards();
    printf("NOTE audio plug-ins in this test process: %s\n", audioPlugIns().UTF8String);
    if (avoid) {
        assert(forwards == 0);
        puts("test tone without iOS's HAL: RemoteIO played 440 Hz through the game's path, 0 calls reached iOS's HAL: PASS");
    } else {
        assert(forwards > 0);
        printf("test tone with iOS's HAL (switch off): RemoteIO played 440 Hz, %u calls handed to iOS's HAL: PASS\n", forwards);
    }
} }
