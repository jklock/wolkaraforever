#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^TKCurseForgeCompletion)(id _Nullable value, NSError *_Nullable error);

// One of the sort fields CurseForge offers for a project list.
//
// The wire value is what `sortField=` carries and is never shown to a person. The
// localization key is what every visible control resolves through `WKLocalized`, so the
// toolbar title, the menu titles, the compact fallback rows and the accessibility labels all
// come from this one table instead of each rebuilding the list. Before this existed the sort
// menu built its titles from raw localization keys (`option[1]`) while the button beside it
// localized them, so the same control read two different ways one tap apart.
@interface TKCurseForgeSortField : NSObject
@property (nonatomic, readonly) NSInteger wireValue;
@property (nonatomic, readonly, copy) NSString *titleKey;
// The direction the site starts in for this field. Name and Author read A-Z; the rest read
// largest or newest first.
@property (nonatomic, readonly) BOOL defaultsToAscending;
@end

// The supported fields, in menu order.
FOUNDATION_EXPORT NSArray<TKCurseForgeSortField *> *TKCurseForgeSortFields(void);
// The field for a wire value, or nil for one this build does not offer.
FOUNDATION_EXPORT TKCurseForgeSortField *_Nullable TKCurseForgeSortFieldForWireValue(NSInteger value);
// Featured: what the list shows before the user chooses anything.
FOUNDATION_EXPORT NSInteger TKCurseForgeDefaultSortField(void);

// How a chosen file relates to the running game version. Advisory: it changes what the app
// *says*, never whether an action is allowed.
typedef NS_ENUM(NSInteger, TKCurseForgeCompatibility) {
    // The file carries the Forever game-version tag.
    TKCurseForgeCompatibilityVerified,
    // The file is available but is not tagged for Forever. Installing it is allowed and the
    // app says it is unverified.
    TKCurseForgeCompatibilityUnverified,
};

// A file the client would install, and what it can honestly say about it.
@interface TKCurseForgeFileCandidate : NSObject
@property (nonatomic, readonly, copy) NSDictionary *file;
@property (nonatomic, readonly) TKCurseForgeCompatibility compatibility;
// The `gameVersions` the file declares, for the advisory line. Never nil, possibly empty.
@property (nonatomic, readonly, copy) NSArray<NSString *> *gameVersions;
@end

// The single decision about which of a project's files would be installed.
//
// The browser row and the install path both call this, so the file a row shows is the file the
// button installs. It is also what makes "newer file available" a comparison of file identity
// rather than of version strings.
FOUNDATION_EXPORT TKCurseForgeFileCandidate *_Nullable TKCurseForgeChooseFile(NSArray *_Nullable files,
                                                                             NSString *_Nullable gameVersion);

// Official CurseForge REST v1 client. The key is sent to the API and, per
// CurseForge's current CDN-auth requirement, only to HTTPS *.forgecdn.net URLs
// returned by that API.
@interface TKCurseForgeClient : NSObject
- (instancetype)initWithAPIKey:(NSString *)key;
- (void)categoriesForGameID:(NSInteger)gameID completion:(TKCurseForgeCompletion)completion;
- (void)browseModsWithQuery:(NSString *)query sortField:(NSInteger)sortField sortOrder:(NSString *)sortOrder categoryID:(nullable NSNumber *)categoryID index:(NSUInteger)index completion:(TKCurseForgeCompletion)completion;
// The same search with the filters the CurseForge site offers for this list:
// a game version tag and the add-on class. Nil means no filter.
- (void)browseModsWithQuery:(NSString *)query sortField:(NSInteger)sortField sortOrder:(NSString *)sortOrder
                 categoryID:(nullable NSNumber *)categoryID gameVersion:(nullable NSString *)gameVersion
                    classID:(nullable NSNumber *)classID index:(NSUInteger)index
                 completion:(TKCurseForgeCompletion)completion;

// The file this build would install for a project.
//
// A Forever-tagged, available file wins when there is one. When there is not, the newest
// available file is offered with `TKCurseForgeCompatibilityUnverified` - it is no longer an
// error for a project to have no Forever-tagged file, because a version tag is advice and not
// a gate. A response that is malformed, or a project with no available file at all, is still
// refused: those are broken answers, not compatibility states.
- (void)bestFileForModID:(NSNumber *)modID gameVersion:(NSString *)gameVersion
              completion:(void (^)(TKCurseForgeFileCandidate *_Nullable candidate, NSError *_Nullable error))completion;

// The newest file tagged for the version, kept for callers that genuinely want "none" to mean
// "none". Prefer -bestFileForModID:gameVersion:completion: for anything the user acts on.
- (void)latestFileForModID:(NSNumber *)modID gameVersion:(NSString *)gameVersion completion:(TKCurseForgeCompletion)completion;
- (void)downloadURLForModID:(NSNumber *)modID fileID:(NSNumber *)fileID completion:(TKCurseForgeCompletion)completion;
- (nullable NSURLRequest *)assetRequestForURL:(NSString *)url error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
