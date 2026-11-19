// The game's sound without iOS's HAL (WolkaraForever, 18 Nov 2026).
//
// Why: a power measurement on an iPad Pro 11-inch (M5), iPadOS 26.5 (18 Nov 2026), found a thread in the dispatch queue
// com.apple.BTAudioHALPlugin at 25 % of a core at every step, unchanged with all of the game's sound off, while the
// process had iOS's HAL plug-ins loaded in it (BTAudioHALPlugin.driver and six others) and no Bluetooth audio was
// connected. The guest is the macOS client: its sound engine asks the macOS HAL (AudioHardwareGetProperty,
// AudioHardwareAddPropertyListener, AudioDeviceGetProperty, AudioObject*) for the default output device, and the
// adapters forwarded those calls to iOS's own CoreAudio, whose HAL then runs in the game's process with every
// plug-in. The sound itself never needed it: it plays through RemoteIO (the AudioToolbox adapter maps the HAL
// output unit to RemoteIO) on the app's audio session.
//
// With the switch on (the default), the CoreAudio adapter answers the HAL calls from its own model of one output
// device - the session's route, under AKAudioModelDevice - and the AudioToolbox adapter reports that device to the
// game for RemoteIO, so nothing the game or the adapters do calls iOS's HAL. A call the model cannot answer still goes
// to iOS (logged "audio: HAL fallback (...)"), so the game keeps its sound even then. Off ("WolkaraForeverAudioAvoidHAL"
// stored NO, the Performance Manager's "Battery-saving sound" row) is the old path, for when the iPad has audio problems.
//
// One source, three images: the CoreAudio and AudioToolbox adapters (translation/AKSupport) and the launcher
// (launcher/WoW), which shows the switch. The adapters read it once, at the game's first sound call: a change applies
// at the next game.
#pragma once
#import <Foundation/Foundation.h>

/// The launcher's switch; anything but a stored number reads as on.
static NSString *const AKAudioAvoidHALDefaultsKey = @"WolkaraForeverAudioAvoidHAL";

/// The model's one output device. Any ID works as long as both adapters use the same one; this one is not a small
/// number, so it never meets an ID iOS's HAL hands out (those count up from 1) if a call does fall back to iOS.
static const UInt32 AKAudioModelDevice = 0x57466f75;   // 'WFou'

/// Whether the HAL is avoided, from these defaults: on unless a number NO is stored.
static inline BOOL AKAudioAvoidHALIn(NSUserDefaults *defaults) {
    id value = [defaults objectForKey:AKAudioAvoidHALDefaultsKey];
    return [value isKindOfClass:NSNumber.class] ? [value boolValue] : YES;
}

/// The process's answer, read once (per image) so a game never mixes the two paths.
static inline BOOL AKAudioAvoidHAL(void) {
    static BOOL avoid;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ avoid = AKAudioAvoidHALIn(NSUserDefaults.standardUserDefaults); });
    return avoid;
}
