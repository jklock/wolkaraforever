#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Metadata only. These routines never open, modify, or execute an installed game.
NSArray<NSDictionary *> *TKWoWProducts(void);
// The account region a first run starts in when the user has not chosen one, from the
// region of the device's own locale. The four regions are not countries: the US portal
// serves the Americas and Oceania, Korea and Taiwan have their own, and everywhere else
// is Europe. A client is bound to the region of the account it signs in with, and a
// first install writes the region into the client's own settings once, so a default that
// does not match the account leaves sign-in at "Connecting" for ever. A locale with no
// country, or nil, is Europe - the value every device used to start in.
NSString *TKWoWDefaultRegion(NSLocale * _Nullable locale);
BOOL TKWoWHashValid(NSString *value);
NSString *TKWoWMD5(NSData *data);
NSArray<NSDictionary<NSString *, NSString *> *> * _Nullable TKWoWTable(NSData *data, NSError **error);
NSDictionary<NSString *, NSString *> * _Nullable TKWoWConfig(NSData *data, NSError **error);
// Verifies the encoded header/chunks and decoded content, with an explicit size budget.
NSData * _Nullable TKWoWDecode(NSData *data, NSString *encodingKey, NSString *contentKey,
    NSUInteger expectedSize, NSUInteger limit, NSError **error);
NSArray<NSDictionary *> * _Nullable TKWoWInstall(NSData *data, NSError **error);
NSArray<NSDictionary *> *TKWoWMacFiles(NSArray<NSDictionary *> *entries, NSString *locale, NSString *region);
BOOL TKWoWBuildCurrent(NSArray<NSDictionary *> *installedRows, NSString *product, NSDictionary *latest);
// Looks up a content hash in an already verified encoding manifest.
NSString * _Nullable TKWoWEncodingKey(NSData *data, NSString *contentKey, NSError **error);
NSError *TKWoWError(NSString *message);

NS_ASSUME_NONNULL_END
