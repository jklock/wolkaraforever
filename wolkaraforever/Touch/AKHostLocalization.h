// WolkaraForever: the app's language, asked from inside a compatibility library.
//
// The on-screen keyboard and the performance overlay are WolkaraForever's own user interface, but
// they are compiled into the guest's compatibility libraries (translation/AppKit), which are a
// different binary from the app. They cannot link WKLocalization, and they must not each resolve
// the language for themselves: two answers to "which language" is how half a screen ends up in
// the other one.
//
// So this asks the app. WKLocalization is looked up by name once, in the process the adapter is
// loaded into, and every string goes through it - the setting, the resolution rules and the tables
// stay in one place.
//
// There is a fallback, and it exists for exactly one situation: a standalone adapter test, where
// nothing in the process is the app. Then the same defaults key and the same .lproj files are read
// directly, so a test sees the language it set. A build of the app never takes that path.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// The translated string for `key` in the app's language. Never nil, never a raw key: the app's
/// own fallback chain applies, and the standalone path repeats it.
NSString *AKHostLocalized(NSString *key);

/// The translated format string for `key`, applied here. The words and the conversions both come
/// from the table, so a language can reorder them.
///
/// A key is not a format, so this is not NS_FORMAT_FUNCTION-annotated: the compiler would check
/// the key. wolkaraforever/tools/check_localization.py checks the tables instead.
NSString *AKHostLocalizedFormat(NSString *key, ...);

/// The plural form of `key` that fits `count`, with the app's own form selection: `.zero`, `.one`
/// and `.other`, the first one the table has.
NSString *AKHostLocalizedCount(NSString *key, NSInteger count);

/// @"en" or @"de": what the labels are being drawn in. For VoiceOver's language attribute, so a
/// German label is not read in an English voice.
NSString *AKHostLanguageCode(void);

NS_ASSUME_NONNULL_END
