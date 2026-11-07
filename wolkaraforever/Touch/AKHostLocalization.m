// WolkaraForever: asking the app which language its labels are in. See AKHostLocalization.h.

#import "AKHostLocalization.h"

static NSString *const AKAppLanguageDefaultsKey = @"WolkaraForeverAppLanguage";

// The app's own class, if this process has one. Cached because the answer cannot change within a
// launch of the dylib, and looked up by name because the two binaries do not link each other.
static Class AKLocalizationClass(void) {
    static Class cls; static dispatch_once_t once;
    dispatch_once(&once, ^{ cls = NSClassFromString(@"WKLocalization"); });
    return cls;
}

// A class method with a format cannot be handed a va_list, so the string and the formatting are
// separate steps here: the table supplies the words, this file only applies the arguments.
typedef NSString *(*AKStringMethod)(id, SEL, NSString *);

static AKStringMethod AKLocalizedStringMethod(void) {
    static AKStringMethod method; static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class cls = AKLocalizationClass();
        if (cls) method = (AKStringMethod)[cls methodForSelector:@selector(localizedString:)];
    });
    return method;
}

#pragma mark - The standalone path

// Only reached when nothing in the process is the app: the adapter test. It repeats the app's
// rules deliberately and says so, rather than inventing a second set.
static NSDictionary<NSString *, NSString *> *AKStandaloneTable(NSString *code) {
    NSString *folder = [NSBundle.mainBundle pathForResource:code ofType:@"lproj"];
    if (!folder) return nil;
    id table = [NSDictionary dictionaryWithContentsOfFile:
        [folder stringByAppendingPathComponent:@"Localizable.strings"]];
    return [table isKindOfClass:NSDictionary.class] ? table : nil;
}

static NSString *AKStandaloneLanguageCode(void) {
    NSString *stored = [NSUserDefaults.standardUserDefaults stringForKey:AKAppLanguageDefaultsKey];
    if ([stored isEqual:@"de"]) return @"de";
    if ([stored isEqual:@"en"]) return @"en";
    for (NSString *identifier in NSLocale.preferredLanguages) {
        NSString *primary = [[identifier stringByReplacingOccurrencesOfString:@"_" withString:@"-"]
            componentsSeparatedByString:@"-"].firstObject.lowercaseString;
        if ([primary isEqual:@"de"]) return @"de";
        if ([primary isEqual:@"en"]) return @"en";
    }
    return @"en";
}

static NSString *AKStandaloneString(NSString *key) {
    NSString *code = AKStandaloneLanguageCode();
    NSString *value = AKStandaloneTable(code)[key];
    if (![value isKindOfClass:NSString.class] || !value.length) value = AKStandaloneTable(@"en")[key];
    if ([value isKindOfClass:NSString.class] && value.length) return value;
    NSString *leaf = [key componentsSeparatedByString:@"."].lastObject ?: key;
    NSString *words = [leaf stringByReplacingOccurrencesOfString:@"_" withString:@" "];
    if (!words.length) return @"";
    return [words stringByReplacingCharactersInRange:NSMakeRange(0, 1)
                                         withString:[words substringToIndex:1].uppercaseString];
}

#pragma mark - The public surface

NSString *AKHostLocalized(NSString *key) {
    if (![key isKindOfClass:NSString.class] || !key.length) return @"";
    AKStringMethod method = AKLocalizedStringMethod();
    NSString *text = method ? method(AKLocalizationClass(), @selector(localizedString:), key) : nil;
    return text.length ? text : AKStandaloneString(key);
}

NSString *AKHostLocalizedFormat(NSString *key, ...) {
    NSString *format = AKHostLocalized(key);
    va_list arguments;
    va_start(arguments, key);
    NSString *text = [[NSString alloc] initWithFormat:format arguments:arguments];
    va_end(arguments);
    return text;
}

NSString *AKHostLocalizedCount(NSString *key, NSInteger count) {
    Class cls = AKLocalizationClass();
    if (cls && [cls respondsToSelector:@selector(localizedString:count:)]) {
        NSString *(*method)(id, SEL, NSString *, NSInteger) =
            (NSString *(*)(id, SEL, NSString *, NSInteger))[cls methodForSelector:@selector(localizedString:count:)];
        NSString *text = method ? method(cls, @selector(localizedString:count:), key, count) : nil;
        if (text.length) return text;
    }
    // The standalone path cannot reach the app's plural selection, so it makes the same choice
    // here: zero, one, other - the first form the table has.
    NSArray<NSString *> *forms = count == 0 ? @[@".zero", @".other", @".one"]
        : (count == 1 || count == -1) ? @[@".one", @".other", @".zero"]
        : @[@".other", @".one", @".zero"];
    NSString *code = AKStandaloneLanguageCode();
    for (NSString *form in forms) {
        NSString *value = AKStandaloneTable(code)[[key stringByAppendingString:form]];
        if ([value isKindOfClass:NSString.class] && value.length) return value;
    }
    return AKHostLocalized(key);
}

NSString *AKHostLanguageCode(void) {
    Class cls = AKLocalizationClass();
    if (cls) {
        typedef id (*AKCodeMethod)(id, SEL);
        AKCodeMethod method = (AKCodeMethod)[cls methodForSelector:@selector(currentLanguageCode)];
        NSString *code = method ? method(cls, @selector(currentLanguageCode)) : nil;
        if ([code isKindOfClass:NSString.class] && code.length) return code;
    }
    return AKStandaloneLanguageCode();
}
