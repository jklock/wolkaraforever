// WolkaraForever: the bounded record of the keyboard and dictation feature.
//
// One vocabulary, under one tag, so a device log can answer "what happened to the composition
// and the microphone" without a reader reconstructing it from unrelated sentences. Every line
// carries only an enumerated value - a language tag, a generation number, a result kind, a
// failure reason - so:
//
//   * never a transcript, a draft, or any part of either;
//   * never audio;
//   * never a user, device or controller identifier;
//   * never a key or a usage;
//   * never a free-form message from the SDK, which can quote what it heard.
//
// The names are fixed. A reader - the voice fixture, the device matrix, a person with the log -
// can rely on them:
//
//   composition.commit | composition.cancel
//   permission=granted | permission=denied
//   recognizer.language=<tag>|system
//   recognizer.generation=<n> change=<start|midcapture>
//   recognizer.session.start generation=<n> language=<tag>|system ondevice=1
//   recognizer.session.end generation=<n> outcome=<final|timeout|cancel|error|background|disabled>
//   result=final|partial generation=<n>
//   failure reason=<unavailable|permission|audio|recognizer|timeout|target|languageUnavailable> [fallback=system]
//   audio.restore=ok|failed
//
// The adapter posts `AKTouchDraftCompositionDidChangeNotification` with a phase and nothing
// else, because it is a dylib the app does not link; the app turns that into the two
// composition lines here, so the whole vocabulary is written by one reader. The notification
// is the only producer of a `keyboard-dictation` line outside this module's own code.

#import "../App/WolkaraForeverLog.h"

#define AKKDLog(...) WKLog("keyboard-dictation", __VA_ARGS__)
