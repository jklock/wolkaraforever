// The frame limit: how often the game's frames reach the screen (BatterySettings.h has the rule).
//
// The game paces itself on its CAMetalLayer's drawables, as BackgroundPacing.m explains. A frame it
// presents through its command buffer is turned into a present that stays on screen for at least
// 1/limit (-presentDrawable:afterMinimumDuration:, Metal's own pacing for a layer that no display
// link drives): the panel runs at that rate, the few drawables stay busy for longer, and the game's
// next -nextDrawable waits for one - so its whole loop slows to the limit without any sleep of ours,
// and each frame lines up with the panel's refreshes. Nothing is dropped: a frame the game drew is
// shown. There is no unlimited choice; before the first decision a present is passed through.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#define AK_FRAME_PACING_EXPORT FOUNDATION_EXTERN __attribute__((visibility("default")))

// Paces presents made through instances of `cls` (a command buffer class). Idempotent. The adapter
// calls it for the class of the device's command buffers on the first drawable; tests give their own.
AK_FRAME_PACING_EXPORT void AKFramePacingInstallOnCommandBufferClass(Class cls);
AK_FRAME_PACING_EXPORT BOOL AKFramePacingIsInstalledOnClass(Class cls);
// Re-reads the launcher's row, Low Power Mode and the thermal state. The adapter calls it at load and
// on each power or thermal notification.
AK_FRAME_PACING_EXPORT void AKFramePacingRefresh(void);
// Sets the inputs directly (what -Refresh reads); logs the limit and its reason when either changes.
AK_FRAME_PACING_EXPORT void AKFramePacingUpdate(NSInteger choice, BOOL lowPower, NSInteger thermalState);
// Where the iPad's power comes from: Automatic is 30 on battery and 60 plugged in or unknown. The adapter
// sets it at load and on each UIDeviceBatteryStateDidChangeNotification (battery monitoring on), so it applies live;
// a change of the limit is logged as "frame limit: 30 fps (Automatic, on battery)" and the like.
AK_FRAME_PACING_EXPORT void AKFramePacingSetPowerSource(NSInteger source);
// The AFK saver (the AppKit adapter, which finds this by name): 10 frames a second while dimmed.
AK_FRAME_PACING_EXPORT void AKFramePacingSetIdle(bool idle);
// The limit in force (AKFrameLimitPanelRate before the first decision), and the minimum duration each present
// is given (0 before it).
AK_FRAME_PACING_EXPORT NSInteger AKFramePacingCurrentRate(void);
AK_FRAME_PACING_EXPORT double AKFramePacingMinimumDuration(void);
// Whether the AFK saver's dimmed screen is on now.
AK_FRAME_PACING_EXPORT BOOL AKFramePacingIsIdle(void);

NS_ASSUME_NONNULL_END
