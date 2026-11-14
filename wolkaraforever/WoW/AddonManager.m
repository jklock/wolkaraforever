#import "AddonManager.h"
#import "AddonStore.h"
#import "AddonCredentialStore.h"
#import "CurseForgeClient.h"
#import "AddonUpdateResolver.h"
#import "AddonHubLog.h"
#import "AddonBrowser.h"
#import "../App/WKLocalization.h"
#import "../App/WolkaraForeverTheme.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static NSString *const TKForeverGameVersion=@"1.60.1";

// A record's acquisition route as a person reads it. The stored word is contract - the store
// writes it and the log repeats it - so only the words beside it are translated. An unknown one
// is shown as it came rather than as a key. This is diagnostic detail: it appears in the detail
// sheet's activity line and nowhere that would change what a row can do.
static NSString *TKAddonSourceName(NSString *source) {
    if ([source isEqual:TKAddonProvenanceAPI]) return WKLocalized(@"addons.source.api");
    if ([source isEqual:TKAddonProvenanceBrowser]) return WKLocalized(@"addons.source.browser");
    if ([source isEqual:TKAddonProvenanceFiles] || [source isEqual:@"zip"]) return WKLocalized(@"addons.source.files");
    if ([source isEqual:TKAddonProvenanceUnmanaged] || [source isEqual:@"Existing"]) return WKLocalized(@"addons.source.unmanaged");
    if ([source isEqual:@"WolkaraForever import"]) return WKLocalized(@"addons.source.import");
    return source ?: @"";
}

@interface TKWoWAddon ()
@property(nonatomic, readwrite, copy) NSString *folder;
@property(nonatomic, readwrite, copy) NSString *title;
@property(nonatomic, readwrite, copy, nullable) NSString *version;
@property(nonatomic, readwrite) NSUInteger fileCount;
@end

@implementation TKWoWAddon
@end

// MARK: - Whole-folder backups

// The archive side is Swift. It is looked up by name and called through its implementation, the
// same way the Forever UI archive is, so the Objective-C side has no compile or link dependency
// on it: a host test that does not build Swift still links, and says exactly what is missing.
static Class TKAddonBackupClass(NSError **error) {
    Class archive=NSClassFromString(@"TKAddonBackupArchive");
    if (!archive && error)
        *error=[NSError errorWithDomain:@"WolkaraForever.AddOns" code:2
            userInfo:@{NSLocalizedDescriptionKey:WKLocalized(@"addons.backup.noComponent")}];
    return archive;
}

NSString *TKAddonBackupCreate(NSString *addOnsDirectory, NSError **error) {
    SEL selector=NSSelectorFromString(@"createBackupInAddOnsDirectory:error:");
    Class archive=TKAddonBackupClass(error);
    if (!archive || ![archive respondsToSelector:selector]) return nil;
    IMP implementation=[archive methodForSelector:selector];
    return ((NSString *(*)(id, SEL, NSString *, NSError **))implementation)(archive, selector, addOnsDirectory, error);
}

NSArray<NSString *> *TKAddonBackupNames(NSString *addOnsDirectory, NSError **error) {
    SEL selector=NSSelectorFromString(@"backupNamesInAddOnsDirectory:error:");
    Class archive=TKAddonBackupClass(error);
    if (!archive || ![archive respondsToSelector:selector]) return @[];
    IMP implementation=[archive methodForSelector:selector];
    return ((NSArray<NSString *> *(*)(id, SEL, NSString *, NSError **))implementation)(archive, selector, addOnsDirectory, error);
}

BOOL TKAddonBackupRestore(NSString *name, NSString *addOnsDirectory, NSError **error) {
    SEL selector=NSSelectorFromString(@"restoreBackupNamed:inAddOnsDirectory:error:");
    Class archive=TKAddonBackupClass(error);
    if (!archive || ![archive respondsToSelector:selector]) return NO;
    IMP implementation=[archive methodForSelector:selector];
    return ((BOOL (*)(id, SEL, NSString *, NSString *, NSError **))implementation)(
        archive, selector, name, addOnsDirectory, error);
}

// MARK: - CurseForge browser: columns, icons and cells

// The project list mirrors the CurseForge site's table: the project's artwork
// and name, then Downloads, Top, Latest, Category, Game Version and Author.
// "Action" is not a column: installing is the row's own selection.
typedef NS_OPTIONS(NSUInteger, TKAddonColumn) {
    TKAddonColumnDownloads = 1 << 0,
    TKAddonColumnTop       = 1 << 1,
    TKAddonColumnLatest    = 1 << 2,
    TKAddonColumnCategory  = 1 << 3,
    TKAddonColumnVersion   = 1 << 4,
    TKAddonColumnAuthor    = 1 << 5,
    TKAddonColumnAll       = 0x3f,
};
static NSString *const TKAddonColumnsKey = @"WolkaraForeverAddonColumnsV1";

static NSString *TKAddonColumnTitle(TKAddonColumn column) {
    switch (column) {
        case TKAddonColumnDownloads: return WKLocalized(@"addons.column.downloads");
        case TKAddonColumnTop:       return WKLocalized(@"addons.column.top");
        case TKAddonColumnLatest:    return WKLocalized(@"addons.column.latest");
        case TKAddonColumnCategory:  return WKLocalized(@"addons.column.category");
        case TKAddonColumnVersion:   return WKLocalized(@"addons.column.version");
        case TKAddonColumnAuthor:    return WKLocalized(@"addons.column.author");
        default: return @"";
    }
}
static CGFloat TKAddonColumnWidth(TKAddonColumn column) {
    switch (column) {
        case TKAddonColumnDownloads: return 74;
        case TKAddonColumnTop:       return 38;
        case TKAddonColumnLatest:    return 78;
        case TKAddonColumnCategory:  return 104;
        case TKAddonColumnVersion:   return 100;
        case TKAddonColumnAuthor:    return 86;
        default: return 0;
    }
}
static NSArray<NSNumber *> *TKAddonColumnOrder(void) {
    return @[@(TKAddonColumnDownloads), @(TKAddonColumnTop), @(TKAddonColumnLatest),
             @(TKAddonColumnCategory), @(TKAddonColumnVersion), @(TKAddonColumnAuthor)];
}
// The width of a row's own action - the browser's Install and the installed list's Update.
// Fixed so a row's columns do not move when the action changes its word.
static const CGFloat TKAddonActionWidth = 96;

// The narrowest page that still holds the full column set: the six fixed columns, the gaps
// between them, the artwork, the gap after it, room for a project's name before it is worth
// drawing at all, and the row's own Install action.
BOOL TKAddonRowsAreCompact(CGFloat width) {
    CGFloat columns = 0.0;
    NSArray<NSNumber *> *order = TKAddonColumnOrder();
    for (NSNumber *number in order) columns += TKAddonColumnWidth((TKAddonColumn)number.unsignedIntegerValue);
    CGFloat required = columns + 10.0 * order.count + 46.0 + 10.0 + 180.0 + TKAddonActionWidth + 10.0;
    return width < required;
}
// The site shows `371.4M`; bytes would say `354.2 MB` and read as storage.
static NSString *TKAddonDownloadsText(NSNumber *value) {
    double n=value.doubleValue;
    if (n >= 1e9) return [NSString stringWithFormat:@"%.1fB", n/1e9];
    if (n >= 1e6) return [NSString stringWithFormat:@"%.1fM", n/1e6];
    if (n >= 1e3) return [NSString stringWithFormat:@"%.1fK", n/1e3];
    return [NSString stringWithFormat:@"%.0f", n];
}
static NSString *TKAddonDateText(NSString *iso) {
    if (![iso isKindOfClass:NSString.class] || iso.length < 10) return @"";
    // The site prints MM/dd/yyyy; the API sends ISO-8601.
    NSString *day=[iso substringToIndex:10];
    NSArray<NSString *> *parts=[day componentsSeparatedByString:@"-"];
    if (parts.count==3) return [NSString stringWithFormat:@"%@/%@/%@",parts[1],parts[2],parts[0]];
    return day;
}
// The file this row would install, chosen by the same code the install path uses. A row that
// picked its own file would eventually disagree with the button beside it, and then the row
// would describe a version that is not the one installed.
static TKCurseForgeFileCandidate *TKAddonCandidate(NSDictionary *project, NSString *gameVersion) {
    NSArray *files=[project[@"latestFiles"] isKindOfClass:NSArray.class]?project[@"latestFiles"]:@[];
    return TKCurseForgeChooseFile(files, gameVersion);
}
// The sheet's body used to run edge to edge: the edition panel touched the
// left rounding, the search field and the list touched both sides. Everything
// on this page is inset by this much now, rows and column titles included, so
// the gutters line up down the whole page.
static const CGFloat TKAddonPageMargin = 14;

static UIImage *TKAddonPlaceholderIcon(void) {
    UIImageSymbolConfiguration *configuration=[UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIFontWeightRegular];
    return [UIImage systemImageNamed:@"puzzlepiece.extension" withConfiguration:configuration];
}

// Project artwork. The API's thumbnail URLs are on CurseForge's CDN; only that
// host is fetched, the data is capped, and decoding happens off the main thread.
@interface TKAddonIconLoader : NSObject
+ (instancetype)shared;
- (void)imageForURLString:(NSString *)string completion:(void (^)(UIImage *image))completion;
@end
@implementation TKAddonIconLoader {
    NSCache<NSString *, UIImage *> *_cache;
    NSURLSession *_session;
}
+ (instancetype)shared {
    static TKAddonIconLoader *loader;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ loader=[TKAddonIconLoader new]; });
    return loader;
}
- (instancetype)init {
    if ((self=[super init])) {
        _cache=[NSCache new]; _cache.countLimit=200;
        NSURLSessionConfiguration *configuration=NSURLSessionConfiguration.ephemeralSessionConfiguration;
        configuration.timeoutIntervalForRequest=20;
        _session=[NSURLSession sessionWithConfiguration:configuration];
    }
    return self;
}
- (void)imageForURLString:(NSString *)string completion:(void (^)(UIImage *))completion {
    if (!string.length || !completion) return;
    UIImage *cached=[_cache objectForKey:string];
    if (cached) { completion(cached); return; }
    NSURL *url=[NSURL URLWithString:string];
    NSString *host=url.host.lowercaseString;
    if (![url.scheme.lowercaseString isEqual:@"https"] ||
        !([host isEqual:@"forgecdn.net"] || [host hasSuffix:@".forgecdn.net"])) { completion(nil); return; }
    [[_session dataTaskWithURL:url completionHandler:^(NSData *data,NSURLResponse *response,NSError *failure) {
        (void)failure;
        NSHTTPURLResponse *http=(id)response;
        if (!data.length || data.length>2*1024*1024 || (http && (http.statusCode<200 || http.statusCode>=300))) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
            return;
        }
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
            UIImage *image=[UIImage imageWithData:data];
            if (image) [self->_cache setObject:image forKey:string];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(image); });
        });
    }] resume];
}
@end

@interface TKAddonProjectCell : UITableViewCell
@property (nonatomic, copy) NSString *iconURLString;
// The row's action. Selecting the rest of the row still opens the project's details, which is
// what it did before there was an action here.
@property (nonatomic, copy, nullable) void (^onInstall)(void);
@property (nonatomic, readonly) UIButton *installButton;
- (void)configureWithProject:(NSDictionary *)project file:(NSDictionary *)file
                        rank:(NSString *)rank columns:(NSUInteger)columns
                 gameVersion:(NSString *)gameVersion compact:(BOOL)compact;
- (void)configureWithProject:(NSDictionary *)project file:(NSDictionary *)file
                        rank:(NSString *)rank columns:(NSUInteger)columns
                 gameVersion:(NSString *)gameVersion compact:(BOOL)compact
                installState:(TKAddonInstallState)state;
@end
@implementation TKAddonProjectCell {
    UIImageView *_iconView;
    UILabel *_titleLabel, *_fileLabel;
    NSMutableDictionary<NSNumber *, UILabel *> *_valueLabels;
    NSMutableDictionary<NSNumber *, NSLayoutConstraint *> *_widthConstraints;
}
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    if ((self=[super initWithStyle:style reuseIdentifier:identifier])) {
        self.backgroundColor=[UIColor colorWithRed:0.07 green:0.09 blue:0.13 alpha:1];
        self.selectionStyle=UITableViewCellSelectionStyleDefault;
        _iconView=[[UIImageView alloc] init];
        _iconView.translatesAutoresizingMaskIntoConstraints=NO;
        _iconView.contentMode=UIViewContentModeScaleAspectFill;
        _iconView.clipsToBounds=YES;
        _iconView.layer.cornerRadius=10;
        _iconView.backgroundColor=[UIColor colorWithWhite:1 alpha:0.06];
        _iconView.image=TKAddonPlaceholderIcon();
        _iconView.tintColor=[UIColor colorWithWhite:0.55 alpha:1];
        _iconView.accessibilityIdentifier=@"wow.addons.logo";
        [NSLayoutConstraint activateConstraints:@[
            [_iconView.widthAnchor constraintEqualToConstant:46],
            [_iconView.heightAnchor constraintEqualToConstant:46],
        ]];
        _titleLabel=[UILabel new];
        _titleLabel.font=[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        _titleLabel.textColor=[UIColor colorWithWhite:0.96 alpha:1];
        _titleLabel.numberOfLines=1;
        _titleLabel.lineBreakMode=NSLineBreakByTruncatingTail;
        _titleLabel.accessibilityIdentifier=@"wow.addons.name";
        _fileLabel=[UILabel new];
        _fileLabel.font=[UIFont systemFontOfSize:11.5 weight:UIFontWeightRegular];
        _fileLabel.textColor=[UIColor colorWithWhite:0.62 alpha:1];
        _fileLabel.numberOfLines=1;
        _fileLabel.lineBreakMode=NSLineBreakByTruncatingMiddle;
        _fileLabel.accessibilityIdentifier=@"wow.addons.file";
        UIStackView *text=[ [UIStackView alloc] initWithArrangedSubviews:@[_titleLabel,_fileLabel] ];
        text.axis=UILayoutConstraintAxisVertical; text.spacing=2; text.alignment=UIStackViewAlignmentLeading;
        UIStackView *name=[ [UIStackView alloc] initWithArrangedSubviews:@[_iconView,text] ];
        name.axis=UILayoutConstraintAxisHorizontal; name.spacing=10; name.alignment=UIStackViewAlignmentCenter;
        [name setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
        [name setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
        _valueLabels=[NSMutableDictionary new]; _widthConstraints=[NSMutableDictionary new];
        NSMutableArray *arranged=[@[name] mutableCopy];
        for (NSNumber *number in TKAddonColumnOrder()) {
            TKAddonColumn column=(TKAddonColumn)number.unsignedIntegerValue;
            UILabel *label=[UILabel new];
            label.font=[UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
            label.textColor=[UIColor colorWithWhite:0.82 alpha:1];
            label.numberOfLines=1;
            label.lineBreakMode=NSLineBreakByTruncatingTail;
            label.accessibilityIdentifier=[@"wow.addons.value." stringByAppendingString:TKAddonColumnTitle(column).lowercaseString];
            NSLayoutConstraint *width=[label.widthAnchor constraintEqualToConstant:TKAddonColumnWidth(column)];
            width.active=YES;
            _valueLabels[number]=label; _widthConstraints[number]=width;
            [arranged addObject:label];
        }
        // The row's own action. It is part of the row because the site puts it there and
        // because the alternative - every install starting with a trip to a details sheet -
        // is two taps for the thing the list is for.
        _installButton=[UIButton buttonWithType:UIButtonTypeSystem];
        _installButton.titleLabel.font=[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        _installButton.tintColor=WKGold();
        _installButton.contentHorizontalAlignment=UIControlContentHorizontalAlignmentRight;
        _installButton.accessibilityIdentifier=@"wow.addons.project.install";
        [_installButton addTarget:self action:@selector(tappedInstall) forControlEvents:UIControlEventTouchUpInside];
        [_installButton.widthAnchor constraintEqualToConstant:TKAddonActionWidth].active=YES;
        [arranged addObject:_installButton];
        UIStackView *row=[ [UIStackView alloc] initWithArrangedSubviews:arranged ];
        row.axis=UILayoutConstraintAxisHorizontal; row.spacing=10; row.alignment=UIStackViewAlignmentCenter;
        row.translatesAutoresizingMaskIntoConstraints=NO;
        [self.contentView addSubview:row];
        [NSLayoutConstraint activateConstraints:@[
            [row.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:TKAddonPageMargin],
            [row.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-TKAddonPageMargin],
            [row.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:9],
            [row.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-9],
        ]];
    }
    return self;
}
- (void)prepareForReuse {
    [super prepareForReuse];
    _iconURLString=nil;
    _iconView.image=TKAddonPlaceholderIcon();
    _installButton.enabled=YES;
}

- (void)tappedInstall { if (self.onInstall) self.onInstall(); }
- (void)configureWithProject:(NSDictionary *)project file:(NSDictionary *)file rank:(NSString *)rank
                     columns:(NSUInteger)columns gameVersion:(NSString *)gameVersion compact:(BOOL)compact {
    [self configureWithProject:project file:file rank:rank columns:columns
                   gameVersion:gameVersion compact:compact installState:TKAddonInstallStateIdle];
}
- (void)configureWithProject:(NSDictionary *)project file:(NSDictionary *)file rank:(NSString *)rank
                     columns:(NSUInteger)columns gameVersion:(NSString *)gameVersion compact:(BOOL)compact
                installState:(TKAddonInstallState)state {
    _titleLabel.text=[project[@"name"] isKindOfClass:NSString.class]?project[@"name"]:WKLocalized(@"addons.untitled");
    NSString *fileText=[file[@"displayName"] isKindOfClass:NSString.class]?file[@"displayName"]:@"";
    _fileLabel.text=fileText.length?fileText:([project[@"summary"] isKindOfClass:NSString.class]?project[@"summary"]:@"");
    NSArray *categories=[project[@"categories"] isKindOfClass:NSArray.class]?project[@"categories"]:@[];
    NSDictionary *firstCategory=[categories.firstObject isKindOfClass:NSDictionary.class]?categories.firstObject:nil;
    NSArray *authors=[project[@"authors"] isKindOfClass:NSArray.class]?project[@"authors"]:@[];
    NSDictionary *firstAuthor=[authors.firstObject isKindOfClass:NSDictionary.class]?authors.firstObject:nil;
    NSArray *versions=[file[@"gameVersions"] isKindOfClass:NSArray.class]?file[@"gameVersions"]:@[];
    NSString *version=gameVersion.length?gameVersion:(versions.lastObject?:@"");
    NSDictionary<NSNumber *, NSString *> *texts=@{
        @(TKAddonColumnDownloads): TKAddonDownloadsText(project[@"downloadCount"]),
        @(TKAddonColumnTop): rank?:@"—",
        @(TKAddonColumnLatest): TKAddonDateText(file[@"fileDate"]),
        @(TKAddonColumnCategory): [firstCategory[@"name"] isKindOfClass:NSString.class]?firstCategory[@"name"]:@"",
        @(TKAddonColumnVersion): version,
        @(TKAddonColumnAuthor): [firstAuthor[@"name"] isKindOfClass:NSString.class]?firstAuthor[@"name"]:@"",
    };
    for (NSNumber *number in TKAddonColumnOrder()) {
        TKAddonColumn column=(TKAddonColumn)number.unsignedIntegerValue;
        BOOL visible=(columns & column) && !(compact && column!=TKAddonColumnDownloads && column!=TKAddonColumnVersion);
        UILabel *label=_valueLabels[number];
        label.hidden=!visible;
        label.text=texts[number]?:@"";
    }
    // The action's word is the row's state, never a raw key. A busy row says so and cannot be
    // pressed again; an installed row says it is installed; an author who does not allow API
    // downloads gets an action that explains rather than a button that would 403.
    _installButton.hidden=NO;
    switch (state) {
        case TKAddonInstallStateBusy:
            [_installButton setTitle:WKLocalized(@"addons.action.installing") forState:UIControlStateNormal];
            _installButton.enabled=NO;
            break;
        case TKAddonInstallStateInstalled:
            [_installButton setTitle:WKLocalized(@"addons.action.installed") forState:UIControlStateNormal];
            _installButton.enabled=NO;
            break;
        case TKAddonInstallStateBrowser:
            [_installButton setTitle:WKLocalized(@"addons.action.open") forState:UIControlStateNormal];
            _installButton.enabled=YES;
            break;
        case TKAddonInstallStateUnavailable:
            [_installButton setTitle:WKLocalized(@"addons.action.unavailable") forState:UIControlStateNormal];
            _installButton.enabled=NO;
            break;
        case TKAddonInstallStateFailed:
            [_installButton setTitle:WKLocalized(@"addons.action.retry") forState:UIControlStateNormal];
            _installButton.enabled=YES;
            break;
        case TKAddonInstallStateIdle:
        default:
            [_installButton setTitle:WKLocalized(@"addons.action.install") forState:UIControlStateNormal];
            _installButton.enabled=YES;
            break;
    }
    NSNumber *identifier=[project[@"id"] isKindOfClass:NSNumber.class]?project[@"id"]:nil;
    _installButton.accessibilityIdentifier=identifier
        ? [NSString stringWithFormat:@"wow.addons.project.%@.install", identifier]
        : @"wow.addons.project.install";
    _installButton.accessibilityLabel=[NSString stringWithFormat:@"%@ %@",
        _installButton.titleLabel.text ?: @"", _titleLabel.text ?: @""];
    NSDictionary *logo=[project[@"logo"] isKindOfClass:NSDictionary.class] ? project[@"logo"] : nil;
    NSString *icon=logo[@"thumbnailUrl"];
    if (![icon isKindOfClass:NSString.class] || !icon.length) icon=logo[@"url"];
    if (![icon isKindOfClass:NSString.class]) icon=nil;
    _iconURLString=icon;
    if (icon.length) {
        __weak TKAddonProjectCell *weakSelf=self;
        NSString *wanted=icon;
        [[TKAddonIconLoader shared] imageForURLString:icon completion:^(UIImage *image) {
            TKAddonProjectCell *self=weakSelf; if (!self || ![self->_iconURLString isEqual:wanted]) return;
            if (image) { self->_iconView.image=image; self->_iconView.tintColor=nil; }
        }];
    }
}
@end

// What the installed row is showing about this package's update. Every case is chosen by
// TKAddonUpdateResolve; the row itself never decides. The resolver's result is the contract, and
// this enum is only how the table view spells it. It is in the header because the fixture has to
// assert the same words the page draws.

// One installed package: a checkbox, the package as a person reads it, and - only when there
// really is a newer file this app could install - an Update action.
@interface TKAddonInstalledCell : UITableViewCell
@property (nonatomic, copy, nullable) void (^onToggleSelection)(BOOL selected);
@property (nonatomic, copy, nullable) void (^onUpdate)(void);
@property (nonatomic, copy, nullable) void (^onManage)(void);
// The row's action opens the in-app browser for a project whose archive the API will not hand
// out, and the link sheet for a package that has no project identity yet.
@property (nonatomic, copy, nullable) void (^onBrowser)(void);
@property (nonatomic, copy, nullable) void (^onLink)(void);
@property (nonatomic, readonly) UIButton *checkbox;
@property (nonatomic, readonly) UIButton *updateButton;
- (void)configureWithRecord:(TKAddonRecord *)record selected:(BOOL)selected
                   selectable:(BOOL)selectable state:(TKAddonUpdateState)state
                       detail:(NSString *)detail;
@end

@implementation TKAddonInstalledCell {
    UIButton *_checkbox;
    UIImageView *_iconView;
    UILabel *_titleLabel, *_detailLabel, *_stateLabel;
    UIButton *_updateButton;
    BOOL _showsManage, _showsBrowser, _showsLink;
}
- (UIButton *)checkbox { return _checkbox; }
- (UIButton *)updateButton { return _updateButton; }
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    if ((self=[super initWithStyle:style reuseIdentifier:identifier])) {
        self.backgroundColor=[UIColor colorWithRed:0.07 green:0.09 blue:0.13 alpha:1];
        // The row itself is the always-available management action. Update is a separate
        // inline action and may be unavailable, but every installed package must still explain
        // whether it can be removed and expose Remove when this app owns it.
        self.selectionStyle=UITableViewCellSelectionStyleDefault;
        self.accessibilityTraits=UIAccessibilityTraitButton;
        _checkbox=[UIButton buttonWithType:UIButtonTypeSystem];
        _checkbox.tintColor=WKGold();
        [_checkbox.widthAnchor constraintEqualToConstant:30].active=YES;
        [_checkbox.heightAnchor constraintEqualToConstant:30].active=YES;
        [_checkbox addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
        _iconView=[[UIImageView alloc] init];
        _iconView.translatesAutoresizingMaskIntoConstraints=NO;
        _iconView.contentMode=UIViewContentModeScaleAspectFill;
        _iconView.clipsToBounds=YES;
        _iconView.layer.cornerRadius=9;
        _iconView.backgroundColor=[UIColor colorWithWhite:1 alpha:0.06];
        _iconView.image=TKAddonPlaceholderIcon();
        _iconView.tintColor=[UIColor colorWithWhite:0.55 alpha:1];
        [NSLayoutConstraint activateConstraints:@[
            [_iconView.widthAnchor constraintEqualToConstant:38],
            [_iconView.heightAnchor constraintEqualToConstant:38],
        ]];
        _titleLabel=[UILabel new];
        _titleLabel.font=[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        _titleLabel.textColor=[UIColor colorWithRed:0.9 green:0.72 blue:0.35 alpha:1];
        _titleLabel.numberOfLines=0;
        _titleLabel.accessibilityIdentifier=@"wow.addons.installed.name";
        _detailLabel=[UILabel new];
        _detailLabel.font=[UIFont systemFontOfSize:11.5 weight:UIFontWeightRegular];
        _detailLabel.textColor=[UIColor colorWithWhite:0.75 alpha:1];
        _detailLabel.numberOfLines=0;
        _detailLabel.accessibilityIdentifier=@"wow.addons.installed.detail";
        // The one word about this package's update, in its own line. It used to live only in
        // the action button, which left a package with nothing to do reading as if it had no
        // update state at all.
        _stateLabel=[UILabel new];
        _stateLabel.font=[UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
        _stateLabel.textColor=[UIColor colorWithWhite:0.7 alpha:1];
        _stateLabel.numberOfLines=1;
        _stateLabel.lineBreakMode=NSLineBreakByTruncatingTail;
        UIStackView *text=[[UIStackView alloc] initWithArrangedSubviews:@[_titleLabel,_detailLabel,_stateLabel]];
        text.axis=UILayoutConstraintAxisVertical; text.spacing=2;
        [text setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
        _updateButton=[UIButton buttonWithType:UIButtonTypeSystem];
        _updateButton.titleLabel.font=[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        _updateButton.tintColor=WKGold();
        _updateButton.contentHorizontalAlignment=UIControlContentHorizontalAlignmentRight;
        [_updateButton.widthAnchor constraintEqualToConstant:TKAddonActionWidth].active=YES;
        [_updateButton addTarget:self action:@selector(tappedUpdate) forControlEvents:UIControlEventTouchUpInside];
        UIStackView *row=[[UIStackView alloc] initWithArrangedSubviews:@[_checkbox,_iconView,text,_updateButton]];
        row.axis=UILayoutConstraintAxisHorizontal; row.spacing=10; row.alignment=UIStackViewAlignmentCenter;
        row.translatesAutoresizingMaskIntoConstraints=NO;
        [self.contentView addSubview:row];
        [NSLayoutConstraint activateConstraints:@[
            [row.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:TKAddonPageMargin],
            [row.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-TKAddonPageMargin],
            [row.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:9],
            [row.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-9],
        ]];
    }
    return self;
}
- (void)toggle { if (self.onToggleSelection) self.onToggleSelection(!_checkbox.selected); }
- (void)tappedUpdate {
    if (_showsManage) {
        if (self.onManage) self.onManage();
    } else if (_showsBrowser) {
        if (self.onBrowser) self.onBrowser();
    } else if (_showsLink) {
        if (self.onLink) self.onLink();
    } else if (self.onUpdate) self.onUpdate();
}
- (void)configureWithRecord:(TKAddonRecord *)record selected:(BOOL)selected
                   selectable:(BOOL)selectable state:(TKAddonUpdateState)state
                       detail:(NSString *)detail {
    NSString *identifier=record.identifier ?: @"";
    self.accessibilityIdentifier=[@"wow.addons.installed." stringByAppendingString:identifier];
    _titleLabel.text=record.name ?: identifier;
    _detailLabel.text=detail ?: @"";
    _checkbox.hidden=!selectable;
    _checkbox.selected=selectable && selected;
    UIImage *mark=[UIImage systemImageNamed:_checkbox.selected?@"checkmark.square.fill":@"square"];
    [_checkbox setImage:mark forState:UIControlStateNormal];
    _checkbox.accessibilityIdentifier=[@"wow.addons.select." stringByAppendingString:identifier];
    _checkbox.accessibilityLabel=WKLocalized(@"addons.select.one");
    _checkbox.accessibilityValue=_checkbox.selected?WKLocalized(@"addons.select.on"):WKLocalized(@"addons.select.off");
    _showsManage=NO; _showsBrowser=NO; _showsLink=NO;
    // The word about this package's update, from the same table the button uses. A row whose
    // state changed but whose sentence did not is how a list starts lying.
    NSString *stateKey=nil;
    UIColor *stateColor=[UIColor colorWithWhite:0.7 alpha:1];
    switch (state) {
        case TKAddonUpdateStateAvailable:
            stateKey=@"addons.update.available"; stateColor=WKGold();
            _updateButton.accessibilityIdentifier=[@"wow.addons.update." stringByAppendingString:identifier];
            [_updateButton setTitle:WKLocalized(@"addons.action.update") forState:UIControlStateNormal];
            _updateButton.enabled=YES;
            break;
        case TKAddonUpdateStateBrowser:
            stateKey=@"addons.update.needsBrowser"; stateColor=WKGold();
            _showsBrowser=YES;
            _updateButton.accessibilityIdentifier=[@"wow.addons.update." stringByAppendingString:identifier];
            [_updateButton setTitle:WKLocalized(@"addons.action.open") forState:UIControlStateNormal];
            _updateButton.enabled=YES;
            break;
        case TKAddonUpdateStateBusy:
            stateKey=@"addons.update.checking";
            _updateButton.accessibilityIdentifier=[@"wow.addons.update." stringByAppendingString:identifier];
            [_updateButton setTitle:WKLocalized(@"addons.action.updating") forState:UIControlStateNormal];
            _updateButton.enabled=NO;
            break;
        case TKAddonUpdateStateFailed:
            stateKey=@"addons.update.failedRetry";
            _updateButton.accessibilityIdentifier=[@"wow.addons.update." stringByAppendingString:identifier];
            [_updateButton setTitle:WKLocalized(@"addons.action.retry") forState:UIControlStateNormal];
            _updateButton.enabled=YES;
            break;
        case TKAddonUpdateStateTerminal:
            stateKey=@"addons.update.failedTerminal";
            _updateButton.accessibilityIdentifier=[@"wow.addons.manage." stringByAppendingString:identifier];
            [_updateButton setTitle:WKLocalized(@"addons.action.manage") forState:UIControlStateNormal];
            _updateButton.enabled=YES;
            _showsManage=YES;
            break;
        case TKAddonUpdateStateUpToDate:
            stateKey=@"addons.update.upToDate";
            _updateButton.accessibilityIdentifier=[@"wow.addons.update." stringByAppendingString:identifier];
            [_updateButton setTitle:WKLocalized(@"addons.action.upToDate") forState:UIControlStateNormal];
            _updateButton.enabled=NO;
            break;
        case TKAddonUpdateStateUnlinked:
            stateKey=@"addons.update.unlinked";
            _showsLink=YES;
            _updateButton.accessibilityIdentifier=[@"wow.addons.link." stringByAppendingString:identifier];
            [_updateButton setTitle:WKLocalized(@"addons.action.link") forState:UIControlStateNormal];
            _updateButton.enabled=YES;
            break;
        case TKAddonUpdateStateUnavailable:
            stateKey=@"addons.update.unavailable";
            _updateButton.accessibilityIdentifier=[@"wow.addons.update." stringByAppendingString:identifier];
            [_updateButton setTitle:WKLocalized(@"addons.action.unavailable") forState:UIControlStateNormal];
            _updateButton.enabled=NO;
            break;
        case TKAddonUpdateStateNotChecked:
            // Nothing has asked the provider about this package. The row says so and offers the
            // check, rather than sitting on "Updating…" with nothing running - the state the
            // installed list was seen in on 2026-11-13.
            stateKey=@"addons.update.notChecked";
            _updateButton.accessibilityIdentifier=[@"wow.addons.check." stringByAppendingString:identifier];
            [_updateButton setTitle:WKLocalized(@"addons.action.check") forState:UIControlStateNormal];
            _updateButton.enabled=YES;
            break;
        case TKAddonUpdateStateNotUpdatable:
        case TKAddonUpdateStateUnknown:
        default:
            // Held back, or not checked yet: the row still manages the package.
            stateKey=state==TKAddonUpdateStateNotUpdatable?@"addons.update.heldBack":@"addons.update.notChecked";
            _showsManage=YES;
            _updateButton.accessibilityIdentifier=[@"wow.addons.manage." stringByAppendingString:identifier];
            [_updateButton setTitle:WKLocalized(@"addons.action.manage") forState:UIControlStateNormal];
            _updateButton.enabled=YES;
            // A visible management action explains ownership and opens Remove for packages this
            // app owns. A greyed empty slot made the installed list look inert.
            break;
    }
    _stateLabel.text=WKLocalized(stateKey);
    _stateLabel.textColor=stateColor;
    _stateLabel.accessibilityIdentifier=[@"wow.addons.state." stringByAppendingString:identifier];
    _updateButton.hidden=NO;
    // VoiceOver reads the row as one thing: what it is, and what its update is doing.
    self.accessibilityLabel=[NSString stringWithFormat:@"%@, %@", _titleLabel.text ?: @"", detail ?: @""];
    self.accessibilityValue=_stateLabel.text;
}
@end

// The bundled WolkaraRoue package, as a row with its own explicit Install action. It appears
// only when the launcher's recommendation row asked for it, so the Installed list a person
// reaches from Install Addons is exactly what it was. The version and the archive hash are
// what the verifier accepted, not what the page hopes the archive is.
@interface TKAddonBundledCell : UITableViewCell
@property (nonatomic, copy, nullable) void (^onInstall)(void);
@property (nonatomic, readonly) UIButton *installButton;
- (void)configureWithPackage:(nullable NSDictionary *)package error:(nullable NSError *)error
                        busy:(BOOL)busy installed:(BOOL)installed;
@end
@implementation TKAddonBundledCell {
    UILabel *_titleLabel, *_detailLabel;
    UIButton *_installButton;
}
- (UIButton *)installButton { return _installButton; }
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    if ((self=[super initWithStyle:style reuseIdentifier:identifier])) {
        self.backgroundColor=[UIColor colorWithRed:0.07 green:0.09 blue:0.13 alpha:1];
        self.selectionStyle=UITableViewCellSelectionStyleNone;
        _titleLabel=[UILabel new];
        _titleLabel.font=[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        _titleLabel.textColor=[UIColor colorWithRed:0.9 green:0.72 blue:0.35 alpha:1];
        _titleLabel.numberOfLines=0;
        _titleLabel.accessibilityIdentifier=@"wow.addons.bundled.name";
        _detailLabel=[UILabel new];
        _detailLabel.font=[UIFont systemFontOfSize:11.5 weight:UIFontWeightRegular];
        _detailLabel.textColor=[UIColor colorWithWhite:0.75 alpha:1];
        _detailLabel.numberOfLines=0;
        _detailLabel.accessibilityIdentifier=@"wow.addons.bundled.detail";
        UIStackView *text=[[UIStackView alloc] initWithArrangedSubviews:@[_titleLabel,_detailLabel]];
        text.axis=UILayoutConstraintAxisVertical; text.spacing=2;
        [text setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
        _installButton=[UIButton buttonWithType:UIButtonTypeSystem];
        _installButton.titleLabel.font=[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        _installButton.tintColor=WKGold();
        _installButton.contentHorizontalAlignment=UIControlContentHorizontalAlignmentRight;
        _installButton.accessibilityIdentifier=@"wow.addons.bundled.install";
        [_installButton.widthAnchor constraintEqualToConstant:TKAddonActionWidth].active=YES;
        [_installButton addTarget:self action:@selector(tappedInstall) forControlEvents:UIControlEventTouchUpInside];
        UIStackView *row=[[UIStackView alloc] initWithArrangedSubviews:@[text,_installButton]];
        row.axis=UILayoutConstraintAxisHorizontal; row.spacing=10; row.alignment=UIStackViewAlignmentCenter;
        row.translatesAutoresizingMaskIntoConstraints=NO;
        [self.contentView addSubview:row];
        [NSLayoutConstraint activateConstraints:@[
            [row.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:TKAddonPageMargin],
            [row.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-TKAddonPageMargin],
            [row.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:9],
            [row.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-9],
        ]];
    }
    return self;
}
- (void)tappedInstall { if (self.onInstall) self.onInstall(); }
- (void)configureWithPackage:(NSDictionary *)package error:(NSError *)error
                        busy:(BOOL)busy installed:(BOOL)installed {
    NSString *release=[package[@"release"] isKindOfClass:NSString.class]?package[@"release"]:nil;
    NSString *hash=[package[@"sha256"] isKindOfClass:NSString.class]?package[@"sha256"]:nil;
    _titleLabel.text=WKLocalized(@"addons.bundled.name");
    BOOL verified=release.length>0 && hash.length>0;
    _detailLabel.text=verified?WKLocalizedFormat(@"addons.bundled.detail",release,hash)
                             :(error.localizedDescription?:WKLocalized(@"addons.bundled.unavailable"));
    self.accessibilityValue=_detailLabel.text;
    _installButton.hidden=!verified;
    [_installButton setTitle:WKLocalized(installed?@"addons.bundled.update":@"addons.bundled.install")
                    forState:UIControlStateNormal];
    _installButton.enabled=!busy;
}
@end

@interface TKAddonColumnsHeaderView : UIView
- (void)configureWithColumns:(NSUInteger)columns compact:(BOOL)compact;
@end
@implementation TKAddonColumnsHeaderView {
    NSMutableDictionary<NSNumber *, UILabel *> *_labels;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self=[super initWithFrame:frame])) {
        self.backgroundColor=WKInk();
        UILabel *name=[UILabel new];
        name.text=WKLocalized(@"addons.column.name").uppercaseString;
        name.font=[UIFont systemFontOfSize:10 weight:UIFontWeightSemibold];
        name.textColor=[UIColor colorWithWhite:0.55 alpha:1];
        UIStackView *row=[ [UIStackView alloc] initWithArrangedSubviews:@[name] ];
        _labels=[NSMutableDictionary new];
        for (NSNumber *number in TKAddonColumnOrder()) {
            TKAddonColumn column=(TKAddonColumn)number.unsignedIntegerValue;
            UILabel *label=[UILabel new];
            label.text=TKAddonColumnTitle(column).uppercaseString;
            label.font=[UIFont systemFontOfSize:10 weight:UIFontWeightSemibold];
            label.textColor=[UIColor colorWithWhite:0.55 alpha:1];
            [label.widthAnchor constraintEqualToConstant:TKAddonColumnWidth(column)].active=YES;
            _labels[number]=label;
            [row addArrangedSubview:label];
        }
        row.axis=UILayoutConstraintAxisHorizontal; row.spacing=10; row.alignment=UIStackViewAlignmentCenter;
        row.translatesAutoresizingMaskIntoConstraints=NO;
        [self addSubview:row];
        [NSLayoutConstraint activateConstraints:@[
            [row.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:TKAddonPageMargin],
            [row.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-TKAddonPageMargin],
            [row.topAnchor constraintEqualToAnchor:self.topAnchor],
            [row.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];
    }
    return self;
}
- (void)configureWithColumns:(NSUInteger)columns compact:(BOOL)compact {
    for (NSNumber *number in TKAddonColumnOrder()) {
        TKAddonColumn column=(TKAddonColumn)number.unsignedIntegerValue;
        _labels[number].hidden=!(columns & column) || (compact && column!=TKAddonColumnDownloads && column!=TKAddonColumnVersion);
    }
}
@end

static NSString *TOCValue(NSString *text, NSString *key) {
    NSString *prefix=[@"## " stringByAppendingString:key];
    for (NSString *line in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        if (![line hasPrefix:prefix]) continue;
        NSString *value=[[line substringFromIndex:prefix.length] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (value.length && value.length<=512) return value;
    }
    return nil;
}

static NSString *ReadTOC(NSString *directory, NSString *folder) {
    NSArray<NSString *> *names=[[NSFileManager.defaultManager contentsOfDirectoryAtPath:directory error:NULL] sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
    NSString *preferred=[folder stringByAppendingPathExtension:@"toc"];
    for (NSString *name in names) {
        if (![name.pathExtension.lowercaseString isEqual:@"toc"]) continue;
        if (![name isEqual:preferred] && [names containsObject:preferred]) continue;
        NSData *data=[NSData dataWithContentsOfFile:[directory stringByAppendingPathComponent:name] options:0 error:NULL];
        if (!data.length || data.length>256*1024) continue;
        NSString *text=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (!text) text=[[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
        if (text) return text;
    }
    return nil;
}

NSArray<TKWoWAddon *> *TKWoWAddonsAtDirectory(NSString *directory) {
    NSFileManager *manager=NSFileManager.defaultManager;
    NSArray<NSString *> *names=[[manager contentsOfDirectoryAtPath:directory error:NULL] sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
    NSMutableArray<TKWoWAddon *> *addons=[NSMutableArray new];
    for (NSString *name in names) {
        if (!name.length || [name hasPrefix:@"."]) continue;
        NSString *path=[directory stringByAppendingPathComponent:name];
        NSURL *url=[NSURL fileURLWithPath:path]; NSNumber *directoryValue=nil;
        if (![url getResourceValue:&directoryValue forKey:NSURLIsDirectoryKey error:NULL] || !directoryValue.boolValue) continue;
        NSString *toc=ReadTOC(path,name);
        if (!toc) continue;
        NSDirectoryEnumerator *files=[manager enumeratorAtURL:[NSURL fileURLWithPath:path] includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles|NSDirectoryEnumerationSkipsPackageDescendants errorHandler:nil];
        NSUInteger count=0; while ([files nextObject]) count++;
        TKWoWAddon *addon=[TKWoWAddon new]; addon.folder=name;
        addon.title=TOCValue(toc,@"Title:")?:name;
        addon.version=TOCValue(toc,@"Version:"); addon.fileCount=count;
        [addons addObject:addon];
    }
    return addons;
}

@interface TKWoWAddonManagerViewController () <UIDocumentPickerDelegate, UISearchBarDelegate>
@property(nonatomic, copy) NSString *addOnsDirectory;
@property(nonatomic, copy) NSString *edition;
@property(nonatomic, copy) NSArray<TKWoWAddon *> *addons;
@property(nonatomic) UISegmentedControl *mode;
@property(nonatomic) TKAddonStore *store;
@property(nonatomic) TKAddonCredentialStore *credentials;
@property(nonatomic) UISearchBar *search;
@property(nonatomic) NSArray<NSDictionary *> *results;
@property(nonatomic) NSInteger sortField;
@property(nonatomic, copy) NSString *sortOrder;
@property(nonatomic) NSNumber *categoryID;
@property(nonatomic, copy) NSString *categoryLabel;
@property(nonatomic) NSUInteger totalCount;
@property(nonatomic) BOOL loadingMore;
@property(nonatomic) BOOL startInBrowse;
// The recommendation the launcher asked for, the project it is filtered to, and the bundled
// package it offers. `None` leaves every one of these exactly as it was before this page had a
// recommendation mode at all.
@property(nonatomic) TKAddonRecommendation recommendation;
@property(nonatomic, copy, nullable) NSNumber *recommendedProjectID;
@property(nonatomic, copy, nullable) NSDictionary *bundledPackage;
@property(nonatomic, copy, nullable) NSError *bundledPackageError;
@property(nonatomic) BOOL bundledInstalling;
@property(nonatomic) NSArray<NSDictionary *> *categories;
@property(nonatomic,copy) NSString *browseStatus;
// The site's list controls: a game-version filter, the seven sort fields and
// the columns that can be shown. The filter and columns are remembered.
@property(nonatomic,copy) NSString *gameVersion;
@property(nonatomic) NSUInteger columns;
@property(nonatomic) UILabel *countLabel;
@property(nonatomic) UIButton *sortButton, *filterButton, *columnsButton;
// The installed list's toolbar, sharing the browse toolbar's row so the mode change does not
// move every row down.
@property(nonatomic) UILabel *selectionLabel;
@property(nonatomic) UIButton *selectAllButton, *clearSelectionButton, *updateSelectedButton, *updateAllButton;
// The refresh control is its own action from now on. It used to be wired straight to
// -reloadAddons, which reloads the filesystem and nothing else: in Browse it left the results,
// the categories and the count showing whatever the provider had said at the last keystroke.
@property(nonatomic) UIBarButtonItem *refreshItem;
// Bumped by every browse request. A reply that arrives with a generation behind the current one
// is dropped, so a slow page cannot overwrite a newer search.
@property(nonatomic) NSUInteger browseGeneration;
@property(nonatomic) BOOL refreshing;
// Package identifiers the user has ticked. Selection never mutates a file by itself.
@property(nonatomic) NSMutableSet<NSString *> *selected;
// The newest installable file for a package, by identifier, and what the row should say.
@property(nonatomic) NSMutableDictionary<NSString *, NSDictionary *> *updateCandidates;
// The resolver's answer per package, keyed by record `uuid`. Not a version string and not a
// folder name: whatever TKAddonUpdateResolve says, and nothing else.
@property(nonatomic) NSMutableDictionary<NSString *, NSNumber *> *updateResults;
// What the provider actually said, and what went wrong, keyed the same way. Keeping the raw
// answer apart from the decision is what lets a relaunch restore a row's word without pretending
// a check is running.
@property(nonatomic) NSMutableDictionary<NSString *, NSDictionary *> *updateAnswers;
@property(nonatomic) NSMutableDictionary<NSString *, NSString *> *updateFailures;
// Packages a metadata sweep is currently asking about.
@property(nonatomic) NSMutableSet<NSString *> *checkingPackages;
// Packages whose archive is being downloaded and installed right now.
@property(nonatomic) NSMutableSet<NSString *> *downloadingPackages;
// My Add-ons' own view state. Search, sort and filter change what is drawn and nothing else.
@property(nonatomic) NSString *installedQuery;
@property(nonatomic) NSInteger installedSort;
@property(nonatomic) NSInteger installedFilter;
// The Discover sections: arrays of project dictionaries, as the API answered them.
@property(nonatomic) NSArray<NSDictionary *> *discoverSections;
@property(nonatomic) NSString *discoverStatus;
@property(nonatomic) BOOL discoverLoading;
@property(nonatomic) UIButton *createGroupButton, *installedFilterButton, *installedSortButton;
@property(nonatomic) TKAddonHubTab tab;
@property(nonatomic) NSUInteger updateGeneration;
@property(nonatomic) BOOL checkingUpdates;
// A bulk run the player started and can still cancel. Cancelling stops the packages that have
// not started, never the one that is mid-commit.
@property(nonatomic) BOOL bulkCancelled;
// CurseForge project ids whose install is in flight, so the row can say "Installing…" and a
// second tap cannot start a second download.
@property(nonatomic) NSMutableSet<NSNumber *> *installing;
@property(nonatomic) BOOL bulkUpdating;
// The update sweep: the packages still to ask about, the client that is asking, and the
// generation that says whether an answer is still wanted.
@property(nonatomic) NSMutableArray<TKAddonRecord *> *updateQueue;
@property(nonatomic) TKCurseForgeClient *updateClient;
// The bulk update: the packages still to do, and how many failed.
@property(nonatomic) NSMutableArray<TKAddonRecord *> *bulkQueue;
@property(nonatomic) NSUInteger bulkFailures;
// Packages the run had to leave to the in-app browser, reported when it finishes.
@property(nonatomic) NSUInteger bulkNeedsBrowser;
@property(nonatomic, copy) NSString *bulkStatus;
@end

@implementation TKWoWAddonManagerViewController
- (instancetype)initWithAddOnsDirectory:(NSString *)directory edition:(NSString *)edition {
    return [self initWithAddOnsDirectory:directory edition:edition recommendation:TKAddonRecommendationNone];
}
- (instancetype)initWithAddOnsDirectory:(NSString *)directory edition:(NSString *)edition browse:(BOOL)browse {
    if (!(self=[self initWithAddOnsDirectory:directory edition:edition recommendation:TKAddonRecommendationNone])) return nil;
    _startInBrowse=browse;
    _tab=browse?TKAddonHubTabBrowse:TKAddonHubTabMyAddOns;
    return self;
}
- (instancetype)initWithAddOnsDirectory:(NSString *)directory edition:(NSString *)edition
                         recommendation:(TKAddonRecommendation)recommendation {
    if (!(self=[super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    _recommendation=recommendation;
    // Mac-Ever is a Browse list of exactly one project, so it starts where that list lives.
    // The bundled package is a row in My Add-ons, so that mode starts there.
    _startInBrowse=recommendation==TKAddonRecommendationMacEver;
    _tab=_startInBrowse?TKAddonHubTabBrowse:TKAddonHubTabMyAddOns;
    _recommendedProjectID=recommendation==TKAddonRecommendationMacEver?@1733200:nil;
    _addOnsDirectory=directory.copy; _edition=edition.copy; _addons=@[]; self.title=WKLocalized(@"addons.title").uppercaseString;
    _store=[[TKAddonStore alloc] initWithAddOnsDirectory:directory product:@"wowf" gameVersion:TKForeverGameVersion]; _results=@[]; _sortField=TKCurseForgeDefaultSortField(); _sortOrder=@"desc";
    _credentials=[TKAddonCredentialStore new];
    _gameVersion=TKForeverGameVersion;
    _selected=[NSMutableSet new]; _installing=[NSMutableSet new];
    _updateCandidates=[NSMutableDictionary new]; _updateResults=[NSMutableDictionary new];
    _downloadingPackages=[NSMutableSet new];
    _installedQuery=@""; _installedSort=0; _installedFilter=0;
    _discoverSections=@[];
    NSNumber *savedColumns=[NSUserDefaults.standardUserDefaults objectForKey:TKAddonColumnsKey];
    _columns=savedColumns?savedColumns.unsignedIntegerValue:TKAddonColumnAll;
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
    // The launcher's own colours, from WolkaraForeverTheme, so this screen and the voice
    // screens cannot drift apart again.
    self.view.backgroundColor=WKInk();
    // Navy, not clear. A transparent table shows whatever is behind it, and behind a
    // sheet is the presentation container, which is white: as a popup this page had a
    // white body under a navy navigation bar. Measured in the fixture on 2026-10-16.
    self.tableView.backgroundColor=WKInk();
    self.tableView.separatorStyle=UITableViewCellSeparatorStyleNone;
    self.navigationItem.largeTitleDisplayMode=UINavigationItemLargeTitleDisplayModeNever;
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:WKLocalized(@"common.done") style:UIBarButtonItemStyleDone target:self action:@selector(done)];
    self.navigationItem.leftBarButtonItem.tintColor=WKGold();
    _refreshItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refreshMetadata)];
    _refreshItem.accessibilityIdentifier=@"wow.addons.refresh";
    self.navigationItem.rightBarButtonItems=@[
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(importAddon)],
        _refreshItem
    ];
    self.navigationItem.rightBarButtonItems[0].accessibilityIdentifier=@"wow.addons.import";
    self.navigationItem.rightBarButtonItems[1].accessibilityIdentifier=@"wow.addons.refresh";
    self.tableView.accessibilityIdentifier=@"wow.addons";
    self.tableView.tableHeaderView=[self header];
    [self reloadAddons];
    // Resolve the bundled package after the installed list, because the row's own word
    // (Install or Update) depends on whether this store already owns WolkaraRoue.
    if (_recommendation==TKAddonRecommendationWolkaraRoue) [self reloadBundledPackage];
    [self updateToolbar];
    if (_startInBrowse) {
        [self selectTab:TKAddonHubTabBrowse];
        // No key is a named state, not an empty page: the footer says what is missing, and
        // Refresh runs the same explicit key prompt it always has.
        if (![self hasKey]) { _browseStatus=WKLocalized(@"addons.enterKey.long"); [self updateToolbar]; [self.tableView reloadData]; }
    }
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    // UITableView does not re-size a tableHeaderView after it has accepted the view. This page
    // is commonly created before a popover/sheet reaches its final width, so leaving the
    // original frame here made the constrained header remain narrow beside full-width rows.
    UIView *header=self.tableView.tableHeaderView;
    CGFloat width=CGRectGetWidth(self.tableView.bounds);
    if (header && width>0 && fabs(CGRectGetWidth(header.frame)-width)>0.5) {
        CGRect frame=header.frame;
        frame.size.width=width;
        header.frame=frame;
        self.tableView.tableHeaderView=header;
    }
}
- (UIView *)header {
    UIColor *gold=WKGold();
    // Laid out with constraints against this view's own layout margins, which inherit the
    // table's. The frames this replaces were computed from the table's width when the header
    // was created - before the sheet had its final size - and then stretched by an autoresizing
    // mask, so the edition panel hung fourteen points past the right edge of the table and the
    // whole page read as ragged next to cells inset by sixteen. Measured in the fixture on
    // 2026-10-22.
    UIView *header=[[UIView alloc] initWithFrame:CGRectMake(0,0,MAX(CGRectGetWidth(self.tableView.bounds),320),212)];
    header.autoresizingMask=UIViewAutoresizingFlexibleWidth;
    // The header takes the table's own margins, safe area included, so its panels share the
    // rows' gutters. On an iPhone in landscape those margins are asymmetric - the notch is on
    // one side - and a symmetric header would put its panels under the notch while every cell
    // stayed clear of it. Measured in the fixture on 2026-11-09: safe area left 76, right 0.
    header.preservesSuperviewLayoutMargins=YES;
    UILayoutGuide *gutters=header.layoutMarginsGuide;
    UIView *editionPanel=[[UIView alloc] init];
    editionPanel.translatesAutoresizingMaskIntoConstraints=NO;
    editionPanel.backgroundColor=WKPanel(); editionPanel.layer.cornerRadius=14; editionPanel.layer.masksToBounds=YES;
    UILabel *edition=[UILabel new]; edition.text=WKLocalizedFormat(@"addons.edition",_edition);
    edition.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody]; edition.textColor=gold;
    edition.backgroundColor=UIColor.clearColor;
    edition.translatesAutoresizingMaskIntoConstraints=NO;
    [editionPanel addSubview:edition];
    [header addSubview:editionPanel];
    _mode=[[UISegmentedControl alloc] initWithItems:@[
        WKLocalized(@"addons.tab.myAddons"),
        WKLocalized(@"addons.tab.discover"),
        WKLocalized(@"addons.tab.browse") ]];
    _mode.selectedSegmentIndex=(NSInteger)_tab; _mode.selectedSegmentTintColor=gold;
    _mode.accessibilityIdentifier=@"wow.addons.tabs";
    [_mode setTitleTextAttributes:@{NSForegroundColorAttributeName:UIColor.blackColor} forState:UIControlStateSelected];
    [_mode setTitleTextAttributes:@{NSForegroundColorAttributeName:[UIColor colorWithWhite:0.72 alpha:1]} forState:UIControlStateNormal];
    [_mode addTarget:self action:@selector(changeMode:) forControlEvents:UIControlEventValueChanged];
    _mode.translatesAutoresizingMaskIntoConstraints=NO;
    [header addSubview:_mode];
    _search=[UISearchBar new]; _search.placeholder=WKLocalized(@"addons.search"); _search.searchBarStyle=UISearchBarStyleMinimal; _search.delegate=self;
    _search.translatesAutoresizingMaskIntoConstraints=NO;
    [header addSubview:_search];

    // The list toolbar, where the site puts its count, sort, filters and column picker.
    _countLabel=[UILabel new];
    _countLabel.font=[UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    _countLabel.textColor=[UIColor colorWithWhite:0.62 alpha:1];
    _countLabel.accessibilityIdentifier=@"wow.addons.count";
    [_countLabel setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    // The count gives way to the buttons beside it rather than clipping their titles: it is a
    // sentence that truncates gracefully, they are menu names that must stay readable.
    [_countLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    _sortButton=[self toolbarButton:@"wow.addons.sort" title:WKLocalized(@"addons.sort")];
    _filterButton=[self toolbarButton:@"wow.addons.filters" title:WKLocalized(@"addons.filters")];
    _columnsButton=[self toolbarButton:@"wow.addons.columns" title:WKLocalized(@"addons.columns")];
    // The installed list's own toolbar. Same row, same place, because a second row of controls
    // would move every row down whenever the mode changed.
    _selectionLabel=[UILabel new];
    _selectionLabel.font=[UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    _selectionLabel.textColor=[UIColor colorWithWhite:0.62 alpha:1];
    _selectionLabel.accessibilityIdentifier=@"wow.addons.selection.count";
    [_selectionLabel setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [_selectionLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    _selectAllButton=[self toolbarButton:@"wow.addons.selectAll" title:WKLocalized(@"addons.select.all")];
    _clearSelectionButton=[self toolbarButton:@"wow.addons.clearSelection" title:WKLocalized(@"addons.select.clear")];
    _updateSelectedButton=[self toolbarButton:@"wow.addons.updateSelected" title:WKLocalized(@"addons.select.updateSelected")];
    _updateAllButton=[self toolbarButton:@"wow.addons.updateAll" title:WKLocalized(@"addons.updateAll")];
    // My Add-ons' own controls. They change what the list draws; none of them touches a file.
    _createGroupButton=[self toolbarButton:@"wow.addons.group.create" title:WKLocalized(@"addons.group.create")];
    _installedSortButton=[self toolbarButton:@"wow.addons.myaddons.sort" title:WKLocalized(@"addons.myaddons.sort")];
    _installedFilterButton=[self toolbarButton:@"wow.addons.myaddons.filter" title:WKLocalized(@"addons.myaddons.filter")];
    _createGroupButton.showsMenuAsPrimaryAction=NO;
    [_createGroupButton addTarget:self action:@selector(tappedCreateGroup) forControlEvents:UIControlEventTouchUpInside];
    _selectAllButton.showsMenuAsPrimaryAction=NO;
    _clearSelectionButton.showsMenuAsPrimaryAction=NO;
    _updateSelectedButton.showsMenuAsPrimaryAction=NO;
    _updateAllButton.showsMenuAsPrimaryAction=NO;
    [_selectAllButton addTarget:self action:@selector(selectAll) forControlEvents:UIControlEventTouchUpInside];
    [_clearSelectionButton addTarget:self action:@selector(clearSelection) forControlEvents:UIControlEventTouchUpInside];
    [_updateSelectedButton addTarget:self action:@selector(tappedUpdateSelected) forControlEvents:UIControlEventTouchUpInside];
    [_updateAllButton addTarget:self action:@selector(tappedUpdateAll) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *toolbar=[[UIStackView alloc] initWithArrangedSubviews:@[_countLabel,_sortButton,_filterButton,_columnsButton,
        _installedSortButton,_installedFilterButton,_createGroupButton,
        _selectionLabel,_selectAllButton,_clearSelectionButton,_updateSelectedButton,_updateAllButton]];
    toolbar.axis=UILayoutConstraintAxisHorizontal; toolbar.spacing=10; toolbar.alignment=UIStackViewAlignmentCenter;
    toolbar.translatesAutoresizingMaskIntoConstraints=NO;
    [header addSubview:toolbar];
    // 14 + 42 + 16 + 36 + 8 + 44 + 8 + 34 + 10 = 212, the height the fixture measures. Kept as
    // constraints rather than offsets so a wider page widens the panels instead of moving them.
    [NSLayoutConstraint activateConstraints:@[
        [editionPanel.leadingAnchor constraintEqualToAnchor:gutters.leadingAnchor constant:TKAddonPageMargin],
        [editionPanel.trailingAnchor constraintEqualToAnchor:gutters.trailingAnchor constant:-TKAddonPageMargin],
        [editionPanel.topAnchor constraintEqualToAnchor:header.topAnchor constant:14],
        [editionPanel.heightAnchor constraintEqualToConstant:42],
        [edition.leadingAnchor constraintEqualToAnchor:editionPanel.leadingAnchor constant:14],
        [edition.trailingAnchor constraintEqualToAnchor:editionPanel.trailingAnchor constant:-14],
        [edition.centerYAnchor constraintEqualToAnchor:editionPanel.centerYAnchor],
        [_mode.leadingAnchor constraintEqualToAnchor:gutters.leadingAnchor constant:TKAddonPageMargin],
        [_mode.trailingAnchor constraintEqualToAnchor:gutters.trailingAnchor constant:-TKAddonPageMargin],
        [_mode.topAnchor constraintEqualToAnchor:editionPanel.bottomAnchor constant:16],
        [_mode.heightAnchor constraintEqualToConstant:36],
        [_search.leadingAnchor constraintEqualToAnchor:gutters.leadingAnchor constant:TKAddonPageMargin],
        [_search.trailingAnchor constraintEqualToAnchor:gutters.trailingAnchor constant:-TKAddonPageMargin],
        [_search.topAnchor constraintEqualToAnchor:_mode.bottomAnchor constant:8],
        [_search.heightAnchor constraintEqualToConstant:44],
        [toolbar.leadingAnchor constraintEqualToAnchor:gutters.leadingAnchor constant:TKAddonPageMargin],
        [toolbar.trailingAnchor constraintEqualToAnchor:gutters.trailingAnchor constant:-TKAddonPageMargin],
        [toolbar.topAnchor constraintEqualToAnchor:_search.bottomAnchor constant:8],
        [toolbar.heightAnchor constraintEqualToConstant:34],
        // Minimum widths, not fixed ones: the titles are localized sentences and must be able to
        // grow. The count label beside them absorbs the difference.
        [_sortButton.widthAnchor constraintGreaterThanOrEqualToConstant:96],
        [_filterButton.widthAnchor constraintGreaterThanOrEqualToConstant:92],
        [_columnsButton.widthAnchor constraintGreaterThanOrEqualToConstant:72],
        [_selectAllButton.widthAnchor constraintGreaterThanOrEqualToConstant:84],
        [_clearSelectionButton.widthAnchor constraintGreaterThanOrEqualToConstant:64],
        [_updateSelectedButton.widthAnchor constraintGreaterThanOrEqualToConstant:132],
        [_updateAllButton.widthAnchor constraintGreaterThanOrEqualToConstant:96],
        [_createGroupButton.widthAnchor constraintGreaterThanOrEqualToConstant:96],
        [_installedSortButton.widthAnchor constraintGreaterThanOrEqualToConstant:84],
        [_installedFilterButton.widthAnchor constraintGreaterThanOrEqualToConstant:84],
    ]];
    return header;
}
- (UIButton *)toolbarButton:(NSString *)identifier title:(NSString *)title {
    UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font=[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    button.titleLabel.lineBreakMode=NSLineBreakByTruncatingTail;
    button.tintColor=WKGold();
    button.contentHorizontalAlignment=UIControlContentHorizontalAlignmentRight;
    button.showsMenuAsPrimaryAction=YES;
    button.accessibilityIdentifier=identifier;
    // The sort and filter titles are sentences, not fixed words: "Filters: Forever (1.60.1)"
    // is wider than "Filters", and the German "Sortierung: Zuletzt aktualisiert" is wider
    // again. A fixed width clipped them on the iPad (seen live on 2026-11-05: the filter read
    // "Filter...1.60.1)"). These hug their title and give way only to the count beside them.
    [button setContentHuggingPriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];
    [button setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    return button;
}
- (void)updateToolbar {
    BOOL browse=_tab==TKAddonHubTabBrowse;
    BOOL myAddOns=_tab==TKAddonHubTabMyAddOns;
    _countLabel.hidden=!browse || ![self hasKey]; _sortButton.hidden=!browse || ![self hasKey];
    _filterButton.hidden=!browse || ![self hasKey]; _columnsButton.hidden=!browse || ![self hasKey];
    _installedSortButton.hidden=!myAddOns; _installedFilterButton.hidden=!myAddOns; _createGroupButton.hidden=!myAddOns;
    _selectionLabel.hidden=!myAddOns; _selectAllButton.hidden=!myAddOns; _clearSelectionButton.hidden=!myAddOns;
    _updateSelectedButton.hidden=!myAddOns; _updateAllButton.hidden=!myAddOns;
    self.navigationItem.rightBarButtonItems[0].enabled=!self.bulkUpdating;
    _refreshItem.enabled=!_refreshing && !self.bulkUpdating && !_discoverLoading;
    if (_tab==TKAddonHubTabDiscover) { _selectionLabel.hidden=YES; return; }
    if (!browse) {
        NSUInteger selectable=0;
        for (TKAddonRecord *record in _store.records) if ([self recordIsSelectable:record]) selectable+=1;
        NSUInteger selected=_selected.count;
        NSUInteger updatable=[self allUpdatableRecords].count;
        // A narrow page holds four controls across, not eight. The selection controls appear
        // only while something is selected - before that they are disabled words taking room
        // from the three controls that always mean something - and the sort and filter
        // controls step aside for them. Every control is still reachable, in the state where
        // it applies.
        BOOL selecting=selected>0;
        _installedSortButton.hidden=selecting; _installedFilterButton.hidden=selecting; _createGroupButton.hidden=selecting;
        _selectionLabel.hidden=!selecting && !self.bulkUpdating;
        _selectAllButton.hidden=selecting; _clearSelectionButton.hidden=!selecting;
        _updateSelectedButton.hidden=!selecting;
        if (self.bulkStatus.length) _selectionLabel.text=self.bulkStatus;
        else if (self.bulkUpdating) _selectionLabel.text=WKLocalized(@"addons.update.workingMany");
        else if (selecting) _selectionLabel.text=WKLocalizedFormat(@"addons.select.summary",(unsigned long)selected,(unsigned long)updatable);
        else _selectionLabel.text=nil;
        // "Select All" belongs to a selection, not to the resting toolbar: with nothing selected
        // the four controls are Sort, Filter, Group and Update All, which is what the page's
        // own plan names and what a narrow page holds without clipping a word.
        _selectAllButton.hidden=!selecting;
        _selectAllButton.enabled=!self.bulkUpdating && selectable>selected;
        _clearSelectionButton.enabled=!self.bulkUpdating && selecting;
        _updateSelectedButton.enabled=!self.bulkUpdating && [self selectedUpdatableRecords].count>0;
        // While a run is live the same button is the way to stop it, and it says so.
        [_updateAllButton setTitle:WKLocalized(self.bulkUpdating?@"addons.action.cancel":@"addons.updateAll")
                          forState:UIControlStateNormal];
        _updateAllButton.enabled=self.bulkUpdating || updatable>0;
        // The current choice is the menu's checkmark, not the button's title: a title carrying it
        // is twice as wide and is what pushed the fourth control off a narrow page.
        [_installedSortButton setTitle:WKLocalized(@"addons.myaddons.sort") forState:UIControlStateNormal];
        [_installedFilterButton setTitle:WKLocalized(@"addons.myaddons.filter") forState:UIControlStateNormal];
        [_createGroupButton setTitle:WKLocalized(@"addons.group.button") forState:UIControlStateNormal];
        _installedSortButton.menu=[self installedSortMenu];
        _installedFilterButton.menu=[self installedFilterMenu];
        _createGroupButton.enabled=!self.bulkUpdating;
        return;
    }
    if (_totalCount) {
        NSNumberFormatter *formatter=[NSNumberFormatter new];
        formatter.locale=WKLocalization.shared.locale;
        formatter.numberStyle=NSNumberFormatterDecimalStyle;
        _countLabel.text=WKLocalizedFormat(@"addons.projectsFound",[formatter stringFromNumber:@(_totalCount)]);
    } else _countLabel.text=_refreshing?WKLocalized(@"addons.refreshing"):([self hasKey]?WKLocalized(@"addons.searching"):WKLocalized(@"addons.enterKey"));
    [_sortButton setTitle:WKLocalizedFormat(@"addons.sort.current",BrowseSortLabel(_sortField)) forState:UIControlStateNormal];
    // The filter's own words: the category's name when one is chosen, otherwise the game-version
    // label a person reads, never a raw version id.
    NSString *filterValue = _categoryLabel ?: (_gameVersion.length ? WKLocalizedFormat(@"addons.filters.forever", _gameVersion) : nil);
    [_filterButton setTitle:filterValue?WKLocalizedFormat(@"addons.filters.active",filterValue):WKLocalized(@"addons.filters") forState:UIControlStateNormal];
    _sortButton.menu=[self sortMenu];
    _filterButton.menu=[self filterMenu];
    _columnsButton.menu=[self columnsMenu];
    BOOL ready=[self hasKey] && !_refreshing;
    _sortButton.enabled=ready; _filterButton.enabled=ready; _columnsButton.enabled=ready;
}

// The refresh control's own action, which is deliberately not -reloadAddons.
//
// -reloadAddons rereads the filesystem and the manifest, which is what the Installed list needs
// and is not a provider refresh: in Browse it neither reloaded the results nor cleared the
// in-memory category metadata, so results and categories could disagree with the provider until
// the user changed another input.
- (void)refreshMetadata {
    if (_refreshing || self.bulkUpdating) return;
    if (_tab==TKAddonHubTabDiscover) { [self fetchDiscover]; return; }
    if (_tab==TKAddonHubTabBrowse) {
        if (![self hasKey]) { [self setupKey]; return; }
        _refreshing=YES; [self updateToolbar];
        [self reloadAddons];
        [self checkForUpdates];
        _refreshing=NO; [self updateToolbar];
        return;
    }
    // My Add-ons: Refresh recalculates every record's state from the store and asks the provider
    // again. It is the list's own action, so it works with no API key at all.
    [self reloadAddons];
    [self checkForUpdates];
    [self updateToolbar];
    [self.tableView reloadData];
}
- (void)refreshBrowseMetadata {
    if (_refreshing || self.bulkUpdating) return;
    if (![self hasKey]) { [self setupKey]; return; }
    _refreshing=YES;
    // A refresh is a new generation: the categories are re-read, the count is cleared and the
    // search starts again from page zero with whatever the current inputs say.
    _categories=nil;
    _browseStatus=WKLocalized(@"addons.refreshing");
    [self updateToolbar];
    [self.tableView reloadData];
    [self fetchPageAtIndex:0 append:NO];
}
- (UIMenu *)sortMenu {
    __weak TKWoWAddonManagerViewController *weakSelf=self;
    NSMutableArray<UIMenuElement *> *fields=[NSMutableArray new];
    for (TKCurseForgeSortField *option in TKCurseForgeSortFields()) {
        NSInteger field=option.wireValue;
        // The title is localized *before* the action is made, from the same table the toolbar
        // button uses. Building it from the raw key was the reason the menu and its own button
        // read differently.
        UIAction *action=[UIAction actionWithTitle:WKLocalized(option.titleKey) image:nil identifier:nil handler:^(UIAction *a) {
            (void)a; TKWoWAddonManagerViewController *self=weakSelf; if(!self)return;
            if (self.sortField==field) self.sortOrder=[self.sortOrder isEqual:@"asc"]?@"desc":@"asc";
            else { self.sortField=field; self.sortOrder=option.defaultsToAscending?@"asc":@"desc"; }
            [self updateToolbar]; [self beginBrowse];
        }];
        action.state=field==_sortField?UIMenuElementStateOn:UIMenuElementStateOff;
        [fields addObject:action];
    }
    UIAction *ascending=[UIAction actionWithTitle:WKLocalized(@"addons.sort.ascending") image:nil identifier:nil handler:^(UIAction *a) {
        (void)a; TKWoWAddonManagerViewController *self=weakSelf; if(!self)return;
        self.sortOrder=@"asc"; [self updateToolbar]; [self beginBrowse];
    }];
    ascending.state=[_sortOrder isEqual:@"asc"]?UIMenuElementStateOn:UIMenuElementStateOff;
    UIAction *descending=[UIAction actionWithTitle:WKLocalized(@"addons.sort.descending") image:nil identifier:nil handler:^(UIAction *a) {
        (void)a; TKWoWAddonManagerViewController *self=weakSelf; if(!self)return;
        self.sortOrder=@"desc"; [self updateToolbar]; [self beginBrowse];
    }];
    descending.state=[_sortOrder isEqual:@"desc"]?UIMenuElementStateOn:UIMenuElementStateOff;
    return [UIMenu menuWithTitle:WKLocalized(@"addons.sort.title") children:@[
        [UIMenu menuWithTitle:WKLocalized(@"addons.sort.field") children:fields],
        [UIMenu menuWithTitle:WKLocalized(@"addons.sort.direction") children:@[ascending,descending]],
    ]];
}
- (UIMenu *)filterMenu {
    __weak TKWoWAddonManagerViewController *weakSelf=self;
    UIAction *allVersions=[UIAction actionWithTitle:WKLocalized(@"addons.filters.allVersions") image:nil identifier:nil handler:^(UIAction *a) {
        (void)a; TKWoWAddonManagerViewController *self=weakSelf; if(!self)return;
        self.gameVersion=nil; [self updateToolbar]; [self beginBrowse];
    }];
    allVersions.state=_gameVersion.length?UIMenuElementStateOff:UIMenuElementStateOn;
    // The human name for the version filter, not the API's own gameVersion id and not a
    // hard-coded "1.60.1 (Forever)". The tier's version is data; only its label is a sentence.
    UIAction *forever=[UIAction actionWithTitle:WKLocalizedFormat(@"addons.filters.forever",TKForeverGameVersion) image:nil identifier:nil handler:^(UIAction *a) {
        (void)a; TKWoWAddonManagerViewController *self=weakSelf; if(!self)return;
        self.gameVersion=TKForeverGameVersion; [self updateToolbar]; [self beginBrowse];
    }];
    forever.state=[_gameVersion isEqual:TKForeverGameVersion]?UIMenuElementStateOn:UIMenuElementStateOff;
    UIAction *allCategories=[UIAction actionWithTitle:WKLocalized(@"addons.filters.allCategories") image:nil identifier:nil handler:^(UIAction *a) {
        (void)a; TKWoWAddonManagerViewController *self=weakSelf; if(!self)return;
        self.categoryID=nil; self.categoryLabel=nil; [self updateToolbar]; [self beginBrowse];
    }];
    allCategories.state=_categoryID?UIMenuElementStateOff:UIMenuElementStateOn;
    UIAction *choose=[UIAction actionWithTitle:_categoryLabel?WKLocalizedFormat(@"addons.filters.category",_categoryLabel):WKLocalized(@"addons.filters.chooseCategory") image:nil identifier:nil handler:^(UIAction *a) {
        (void)a; [weakSelf chooseCategoryFrom:nil];
    }];
    UIAction *clear=[UIAction actionWithTitle:WKLocalized(@"addons.filters.clear") image:nil identifier:nil handler:^(UIAction *a) {
        (void)a; TKWoWAddonManagerViewController *self=weakSelf; if(!self)return;
        self.gameVersion=TKForeverGameVersion; self.categoryID=nil; self.categoryLabel=nil;
        [self updateToolbar]; [self beginBrowse];
    }];
    return [UIMenu menuWithTitle:WKLocalized(@"addons.filters") children:@[
        [UIMenu menuWithTitle:WKLocalized(@"addons.filters.gameVersion") children:@[allVersions,forever]],
        [UIMenu menuWithTitle:WKLocalized(@"addons.column.category") children:@[allCategories,choose]],
        clear,
    ]];
}
- (UIMenu *)columnsMenu {
    __weak TKWoWAddonManagerViewController *weakSelf=self;
    NSMutableArray<UIMenuElement *> *actions=[NSMutableArray new];
    for (NSNumber *number in TKAddonColumnOrder()) {
        TKAddonColumn column=(TKAddonColumn)number.unsignedIntegerValue;
        UIAction *action=[UIAction actionWithTitle:TKAddonColumnTitle(column) image:nil identifier:nil handler:^(UIAction *a) {
            (void)a; TKWoWAddonManagerViewController *self=weakSelf; if(!self)return;
            self.columns = (self.columns & column) ? (self.columns & ~column) : (self.columns | column);
            [NSUserDefaults.standardUserDefaults setObject:@(self.columns) forKey:TKAddonColumnsKey];
            [self updateToolbar]; [self.tableView reloadData];
        }];
        action.state=(_columns & column)?UIMenuElementStateOn:UIMenuElementStateOff;
        [actions addObject:action];
    }
    return [UIMenu menuWithTitle:WKLocalized(@"addons.columns") children:actions];
}
- (void)done { WKDismissPage(self); }
- (void)selectTab:(TKAddonHubTab)tab {
    _tab=tab;
    _mode.selectedSegmentIndex=(NSInteger)tab;
    if (tab==TKAddonHubTabBrowse) {
        if ([self hasKey]) [self beginBrowse]; else _browseStatus=WKLocalized(@"addons.enterKey.long");
    } else if (tab==TKAddonHubTabDiscover) {
        [self fetchDiscover];
    } else {
        // My Add-ons: reread the folder and ask the provider about every linked package. This
        // is the check the page exists for, and it runs because a person opened this tab.
        [self reloadAddons];
        [self checkForUpdates];
    }
    [self updateToolbar];
    [self.tableView reloadData];
}
- (void)changeMode:(UISegmentedControl *)sender {
    NSInteger index=MAX((NSInteger)0,MIN((NSInteger)TKAddonHubTabBrowse,sender.selectedSegmentIndex));
    [self selectTab:(TKAddonHubTab)index];
}
- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
    // The search field is the same control on every tab and means the same thing on two of them:
    // it narrows what is drawn. On Browse it is a query the provider answers.
    if (_tab==TKAddonHubTabMyAddOns) {
        _installedQuery=searchBar.text?:@"";
        [self.tableView reloadData];
        [self updateToolbar];
        return;
    }
    [self beginBrowse];
}
- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    (void)searchBar;
    if (_tab!=TKAddonHubTabMyAddOns) return;
    _installedQuery=searchText?:@"";
    [self.tableView reloadData];
    [self updateToolbar];
}
- (BOOL)hasKey { return [_credentials curseForgeKey:NULL].length>0; }
- (BOOL)canLoadMore { return _results.count>0 && _results.count<_totalCount; }
- (void)beginBrowse { if (_recommendedProjectID) { [self fetchRecommendedProject]; return; } [self fetchPageAtIndex:0 append:NO]; }
- (void)loadMore { if (_loadingMore) return; [self fetchPageAtIndex:_results.count append:YES]; }
// The Mac-Ever recommendation: exactly one project, asked for by id. A search that happened to
// return a project with a similar name is not the project the row names, and a reply carrying
// another id is refused rather than shown.
- (void)fetchRecommendedProject {
    NSString *key=[_credentials curseForgeKey:NULL];
    if (!key.length) { _browseStatus=WKLocalized(@"addons.enterKey.long"); _results=@[]; _totalCount=0; [self.tableView reloadData]; return; }
    _results=@[]; _totalCount=0; _browseStatus=WKLocalized(@"addons.loading"); _loadingMore=YES; [self.tableView reloadData];
    TKCurseForgeClient *client=[[TKCurseForgeClient alloc] initWithAPIKey:key];
    NSUInteger generation=(_browseGeneration+=1);
    NSNumber *projectID=_recommendedProjectID;
    [client projectForModID:projectID completion:^(id value,NSError *error){
        dispatch_async(dispatch_get_main_queue(),^{
            if (generation != self.browseGeneration) return;
            self.loadingMore=NO;
            if (error) { self.browseStatus=error.localizedDescription; }
            else if ([value isKindOfClass:NSDictionary.class]) {
                NSNumber *returned=[value[@"id"] isKindOfClass:NSNumber.class]?value[@"id"]:nil;
                if ([returned isEqual:projectID]) {
                    self.results=@[value]; self.totalCount=1;
                    self.browseStatus=WKLocalizedFormat(@"addons.projectsShown",1UL,1UL);
                } else {
                    self.results=@[]; self.totalCount=0;
                    self.browseStatus=WKLocalized(@"addons.recommended.unexpected");
                }
            }
            self.refreshing=NO;
            [self updateToolbar];
            [self.tableView reloadData];
        });
    }];
}
- (void)fetchPageAtIndex:(NSUInteger)index append:(BOOL)append {
    NSString *key=[_credentials curseForgeKey:NULL];
    if (!key.length) { _browseStatus=WKLocalized(@"addons.enterKey.long"); _results=@[]; _totalCount=0; [self.tableView reloadData]; return; }
    if (append) _browseStatus=WKLocalized(@"addons.loadingMore");
    else { _results=@[]; _totalCount=0; _browseStatus=WKLocalized(@"addons.loading"); }
    _loadingMore=YES; [self.tableView reloadData];
    TKCurseForgeClient *client=[[TKCurseForgeClient alloc] initWithAPIKey:key];
    NSUInteger generation=(_browseGeneration+=1);
    [client browseModsWithQuery:_search.text?:@"" sortField:_sortField sortOrder:_sortOrder categoryID:_categoryID
                   gameVersion:_gameVersion classID:nil index:index completion:^(id value,NSError *error){
        dispatch_async(dispatch_get_main_queue(),^{
            // A reply from a search the user has already replaced is not this page's answer.
            // Writing it anyway is how results and categories end up disagreeing with the
            // provider after a refresh. The generation is bumped for every request, including
            // the appends, so a late page one cannot land on top of a new page zero.
            if (generation != self.browseGeneration) return;
            self.loadingMore=NO;
            if (error) { self.browseStatus=error.localizedDescription; }
            else {
                NSArray *page=[value[@"data"] isKindOfClass:NSArray.class]?value[@"data"]:@[];
                self.results=append?[self.results arrayByAddingObjectsFromArray:page]:page;
                NSDictionary *pagination=[value[@"pagination"] isKindOfClass:NSDictionary.class]?value[@"pagination"]:@{};
                NSNumber *total=[pagination[@"totalCount"] isKindOfClass:NSNumber.class]?pagination[@"totalCount"]:nil;
                self.totalCount=total?total.unsignedIntegerValue:MAX(self.results.count,page.count);
                self.browseStatus=WKLocalizedFormat(@"addons.projectsShown",
                    (unsigned long)self.results.count,(unsigned long)MAX(self.totalCount,self.results.count));
            }
            if (!append) { self.refreshing=NO; }
            [self updateToolbar];
            [self.tableView reloadData];
        });
    }];
}
static NSString *BrowseSortLabel(NSInteger field) {
    TKCurseForgeSortField *option=TKCurseForgeSortFieldForWireValue(field);
    return WKLocalized(option?option.titleKey:@"addons.sort.featured");
}
- (void)presentSheet:(UIAlertController *)sheet from:(NSIndexPath *)indexPath {
    // Every popup on this page gets the same bound: at most 85 % of the presenting screen in
    // each dimension, with even margins. UIKit's own iPad sizing is not consulted.
    WKPreparePopupForPresentation(sheet, self.view);
    sheet.popoverPresentationController.sourceView=self.view;
    sheet.popoverPresentationController.sourceRect=indexPath?[self.tableView rectForRowAtIndexPath:indexPath]:CGRectMake(CGRectGetMidX(self.view.bounds),CGRectGetMaxY(self.view.bounds),1,1);
    [self presentViewController:sheet animated:YES completion:^{
        WKConstrainPopupToScreen(sheet, self.view);
    }];
}
- (void)presentSortMenuFrom:(NSIndexPath *)indexPath {
    UIAlertController *sheet=[UIAlertController alertControllerWithTitle:WKLocalized(@"addons.sort.title") message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (TKCurseForgeSortField *option in TKCurseForgeSortFields()) {
        NSInteger field=option.wireValue;
        NSString *title=WKLocalized(option.titleKey);
        [sheet addAction:[UIAlertAction actionWithTitle:field==_sortField?[@"✓ " stringByAppendingString:title]:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){(void)action;
            if (self.sortField==field) self.sortOrder=[self.sortOrder isEqual:@"asc"]?@"desc":@"asc";
            else { self.sortField=field; self.sortOrder=option.defaultsToAscending?@"asc":@"desc"; }
            [self updateToolbar];
            [self beginBrowse];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:WKLocalizedFormat(@"addons.sort.directionValue",[_sortOrder isEqual:@"asc"]?WKLocalized(@"addons.sort.ascending"):WKLocalized(@"addons.sort.descending")) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){(void)action; self.sortOrder=[self.sortOrder isEqual:@"asc"]?@"desc":@"asc"; [self beginBrowse];}]];
    [sheet addAction:[UIAlertAction actionWithTitle:WKLocalized(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
    [self presentSheet:sheet from:indexPath];
}
- (void)chooseCategoryFrom:(NSIndexPath *)indexPath {
    if (_categories.count) { [self presentCategoryMenuFrom:indexPath]; return; }
    NSString *key=[_credentials curseForgeKey:NULL]; if (!key.length) { [self setupKey]; return; }
    _browseStatus=WKLocalized(@"addons.loadingCategories"); [self.tableView reloadData];
    TKCurseForgeClient *client=[[TKCurseForgeClient alloc] initWithAPIKey:key];
    [client categoriesForGameID:1 completion:^(id value,NSError *error){
        dispatch_async(dispatch_get_main_queue(),^{
            if (error) { self.browseStatus=error.localizedDescription; [self.tableView reloadData]; return; }
            NSArray *all=[value isKindOfClass:NSArray.class]?value:@[];
            NSNumber *addOnClass=nil;
            for (NSDictionary *entry in all) if ([entry isKindOfClass:NSDictionary.class] && [entry[@"isClass"] boolValue] && [entry[@"name"] isKindOfClass:NSString.class] && [entry[@"name"] rangeOfString:@"addon" options:NSCaseInsensitiveSearch].location!=NSNotFound && [entry[@"id"] isKindOfClass:NSNumber.class]) { addOnClass=entry[@"id"]; break; }
            NSMutableArray *matched=[NSMutableArray new],*top=[NSMutableArray new];
            for (NSDictionary *entry in all) {
                if (![entry isKindOfClass:NSDictionary.class] || [entry[@"isClass"] boolValue]) continue;
                if (![entry[@"id"] isKindOfClass:NSNumber.class] || ![entry[@"name"] isKindOfClass:NSString.class]) continue;
                if (addOnClass && ![entry[@"classId"] isEqual:addOnClass]) continue;
                NSDictionary *category=@{ @"id":entry[@"id"],@"name":entry[@"name"] };
                [matched addObject:category];
                NSNumber *parent=[entry[@"parentCategoryId"] isKindOfClass:NSNumber.class]?entry[@"parentCategoryId"]:@0;
                if (parent.integerValue==0) [top addObject:category];
            }
            NSArray *categories=top.count?top:(matched.count?matched:nil);
            if (!categories.count) { self.browseStatus=WKLocalized(@"addons.noCategories"); [self.tableView reloadData]; return; }
            self.categories=[categories sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];}];
            [self presentCategoryMenuFrom:indexPath];
        });
    }];
}
- (void)presentCategoryMenuFrom:(NSIndexPath *)indexPath {
    UIAlertController *sheet=[UIAlertController alertControllerWithTitle:WKLocalized(@"addons.filters.categoryTitle") message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:_categoryID?WKLocalized(@"addons.filters.allCategories"):[@"✓ " stringByAppendingString:WKLocalized(@"addons.filters.allCategories")] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){(void)action; self.categoryID=nil; self.categoryLabel=nil; [self beginBrowse];}]];
    for (NSDictionary *category in _categories) {
        [sheet addAction:[UIAlertAction actionWithTitle:[category[@"id"] isEqual:_categoryID]?[@"✓ " stringByAppendingString:category[@"name"]]:category[@"name"] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){(void)action; self.categoryID=category[@"id"]; self.categoryLabel=category[@"name"]; [self updateToolbar]; [self beginBrowse];}]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:WKLocalized(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
    [self presentSheet:sheet from:indexPath];
}
- (void)presentProject:(NSDictionary *)entry {
    NSString *name=[entry[@"name"] isKindOfClass:NSString.class]?entry[@"name"]:WKLocalized(@"addons.untitled");
    NSMutableArray<NSString *> *details=[NSMutableArray new];
    if ([entry[@"summary"] isKindOfClass:NSString.class] && [entry[@"summary"] length]) [details addObject:entry[@"summary"]];
    NSMutableArray<NSString *> *authors=[NSMutableArray new];
    if ([entry[@"authors"] isKindOfClass:NSArray.class]) for (NSDictionary *author in entry[@"authors"]) if ([author isKindOfClass:NSDictionary.class] && [author[@"name"] isKindOfClass:NSString.class]) [authors addObject:author[@"name"]];
    if (authors.count) [details addObject:WKLocalizedFormat(@"addons.by",[authors componentsJoinedByString:@", "])];
    if ([entry[@"downloadCount"] isKindOfClass:NSNumber.class]) [details addObject:WKLocalizedFormat(@"addons.downloads",entry[@"downloadCount"])];
    UIAlertController *sheet=[UIAlertController alertControllerWithTitle:name message:[details componentsJoinedByString:@"\n"] preferredStyle:UIAlertControllerStyleActionSheet];
    // Whether the author lets CurseForge hand the file out through the API at all. The search
    // result says so, so the page can say so instead of letting the user tap Install and collect
    // a 403 that reads like a broken key - which is what happened on the device on 2026-10-22.
    BOOL distribution = ![entry[@"allowModDistribution"] isKindOfClass:NSNumber.class] || [entry[@"allowModDistribution"] boolValue];
    if (distribution) {
        [sheet addAction:[UIAlertAction actionWithTitle:WKLocalized(@"addons.installLatest") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){(void)action;[self installMod:entry];}]];
    } else {
        [sheet setValue:WKLocalizedFormat(@"addons.noDistribution", [details componentsJoinedByString:@"\n"]) forKey:@"message"];
    }
    // Every route out of this sheet stays inside the app. A project the API will not distribute
    // gets the same action word as any other project's Install; it just opens the project's own
    // page in the in-app browser instead of downloading through the API here.
    if ([self projectSlugForEntry:entry].length)
        [sheet addAction:[UIAlertAction actionWithTitle:WKLocalized(distribution?@"addons.openProject":@"addons.action.open") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){(void)action;[self openBrowserForProjectEntry:entry];}]];
    [sheet addAction:[UIAlertAction actionWithTitle:WKLocalized(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
    [self presentSheet:sheet from:nil];
}

// The project's own slug, from the API's `slug` or its `links.websiteUrl`. Nil when the reply
// carries neither, because a search for the name is not that project's page.
- (nullable NSString *)projectSlugForEntry:(NSDictionary *)entry {
    if ([entry[@"slug"] isKindOfClass:NSString.class] && [entry[@"slug"] length]) return entry[@"slug"];
    NSString *website=[entry[@"links"] isKindOfClass:NSDictionary.class] ? entry[@"links"][@"websiteUrl"] : nil;
    if (![website isKindOfClass:NSString.class]) return nil;
    NSURL *url=[NSURL URLWithString:website];
    NSString *slug=url.lastPathComponent;
    return slug.length?slug:nil;
}
- (void)showError:(NSString *)title message:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(),^{
        UIAlertController *alert=[UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:WKLocalized(@"common.ok") style:UIAlertActionStyleDefault handler:nil]];
        [self presentAlert:alert];
    });
}
- (void)providerFailed:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(),^{
        self.browseStatus=error.localizedDescription;
        [self.tableView reloadData];
        [self showProviderError:error];
    });
}
// The provider identity that goes in the manifest. It is built only from values the API gave
// us for *this* project and *this* file: the project id, the file id, the file's own name and
// version, the date the API published it, and the compatibility state that came with the file.
// Nothing here is derived from a display name or a folder name.
- (NSDictionary *)providerIdentityForProject:(NSDictionary *)project file:(NSDictionary *)file
                               compatibility:(TKCurseForgeCompatibility)compatibility {
    NSNumber *projectID=[project[@"id"] isKindOfClass:NSNumber.class]?project[@"id"]:nil;
    NSNumber *fileID=[file[@"id"] isKindOfClass:NSNumber.class]?file[@"id"]:nil;
    if (!projectID || !fileID) return nil;
    NSMutableDictionary *identity=[NSMutableDictionary dictionary];
    identity[TKAddonProviderKind]=@"curseforge";
    identity[TKAddonProviderProjectID]=projectID;
    identity[TKAddonProviderFileID]=fileID;
    if ([file[@"displayName"] isKindOfClass:NSString.class]) identity[TKAddonProviderFileName]=file[@"displayName"];
    if ([file[@"fileName"] isKindOfClass:NSString.class]) identity[TKAddonProviderFileName]=file[@"fileName"];
    if ([file[@"displayName"] isKindOfClass:NSString.class]) identity[TKAddonProviderVersion]=file[@"displayName"];
    if ([file[@"fileDate"] isKindOfClass:NSString.class]) identity[TKAddonProviderPublishedDate]=file[@"fileDate"];
    identity[TKAddonProviderCompatibility]=compatibility==TKCurseForgeCompatibilityVerified
        ? TKAddonCompatibilityVerified : TKAddonCompatibilityUnverified;
    return identity;
}

- (void)installMod:(NSDictionary *)entry {
    NSNumber *modID=[entry[@"id"] isKindOfClass:NSNumber.class]?entry[@"id"]:nil;
    if (!modID) return;
    NSString *name=[entry[@"name"] isKindOfClass:NSString.class]?entry[@"name"]:WKLocalized(@"addons.thisAddon");
    NSString *key=[_credentials curseForgeKey:NULL];
    if (!key.length) { [self setupKey]; return; }
    // Two taps must not become two downloads. The row says what it is doing and the second tap
    // is refused while the first is still in flight.
    if ([_installing containsObject:modID]) return;
    [_installing addObject:modID];
    _browseStatus=WKLocalizedFormat(@"addons.downloading",name);
    [self.tableView reloadData];
    TKCurseForgeClient *client=[[TKCurseForgeClient alloc] initWithAPIKey:key];
    [client bestFileForModID:modID gameVersion:TKForeverGameVersion completion:^(TKCurseForgeFileCandidate *candidate,NSError *error){
        if (error) {
            [self.installing removeObject:modID];
            [self providerFailed:error];
            return;
        }
        [self installCandidate:candidate project:entry replacing:nil client:client name:name];
    }];
}

// Download one file and either import it as a new package or replace an existing one.
- (void)installCandidate:(TKCurseForgeFileCandidate *)candidate project:(NSDictionary *)project
               replacing:(TKAddonRecord *)record client:(TKCurseForgeClient *)client name:(NSString *)name {
    NSDictionary *file=candidate.file;
    NSNumber *modID=[project[@"id"] isKindOfClass:NSNumber.class]?project[@"id"]:nil;
    NSNumber *fileID=[file[@"id"] isKindOfClass:NSNumber.class]?file[@"id"]:nil;
    if (!fileID) {
        if (modID) [_installing removeObject:modID];
        [self providerFailed:[NSError errorWithDomain:@"WolkaraForever.CurseForge" code:1 userInfo:@{NSLocalizedDescriptionKey:WKLocalized(@"addons.error.incompleteFile")}]];
        return;
    }
    NSDictionary *provider=[self providerIdentityForProject:project file:file compatibility:candidate.compatibility];
    // The file record carries the URL when the author allows API distribution. Asking the
    // download-url endpoint for a file that already came with a URL is a request that can only
    // fail - and on 2026-10-22 it did, with a 403 that the app used to report as a rejected key.
    NSString *carried=[file[@"downloadUrl"] isKindOfClass:NSString.class]?file[@"downloadUrl"]:nil;
    dispatch_block_t finish = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            if (modID) [self.installing removeObject:modID];
            if (record) [self.downloadingPackages removeObject:record.uuid ?: record.identifier];
            [self.tableView reloadData];
            [self updateToolbar];
        });
    };
    if (carried.length) {
        [self downloadArchiveAt:carried forClient:client name:name provider:provider record:record compatibility:candidate.compatibility completion:finish];
        return;
    }
    [client downloadURLForModID:modID fileID:fileID completion:^(NSString *url,NSError *downloadError){
        if (downloadError) { if (modID) dispatch_async(dispatch_get_main_queue(), ^{ [self.installing removeObject:modID]; }); [self providerFailed:downloadError]; return; }
        [self downloadArchiveAt:url forClient:client name:name provider:provider record:record compatibility:candidate.compatibility completion:finish];
    }];
}

- (void)downloadArchiveAt:(NSString *)url forClient:(TKCurseForgeClient *)client name:(NSString *)name
                 provider:(NSDictionary *)provider record:(TKAddonRecord *)record
            compatibility:(TKCurseForgeCompatibility)compatibility completion:(dispatch_block_t)completion {
    NSError *requestError=nil;
    NSURLRequest *request=[client assetRequestForURL:url error:&requestError];
    if (!request) { if (completion) completion(); [self providerFailed:requestError]; return; }
    NSURLSessionDownloadTask *task=[[NSURLSession sharedSession] downloadTaskWithRequest:request completionHandler:^(NSURL *location,NSURLResponse *response,NSError *failure){
        (void)response;
        if (failure||!location) { if (completion) completion(); [self providerFailed:failure?:[NSError errorWithDomain:@"WolkaraForever.CurseForge" code:1 userInfo:@{NSLocalizedDescriptionKey:WKLocalized(@"addons.error.noArchive")}]]; return; }
        NSString *path=[NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingString:@".zip"]];
        NSError *moveError=nil; [[NSFileManager defaultManager] moveItemAtURL:location toURL:[NSURL fileURLWithPath:path] error:&moveError];
        NSError *storeError=nil;
        BOOL ok=NO;
        if (!moveError) {
            if (record) ok=[self.store updateRecord:record archiveURL:[NSURL fileURLWithPath:path]
                                            provider:provider provenance:TKAddonProvenanceAPI error:&storeError];
            else ok=[self.store importZIPAtURL:[NSURL fileURLWithPath:path] provider:provider
                                    provenance:TKAddonProvenanceAPI error:&storeError];
        }
        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
        if (completion) completion();
        dispatch_async(dispatch_get_main_queue(),^{
            if (!ok) {
                NSError *cause=moveError?:storeError;
                TKAddonHubLog(TKAddonHubEventRow, @{ TKAddonHubKeyOutcome: @"failed",
                    TKAddonHubKeyProvider: TKAddonProvenanceAPI,
                    TKAddonHubKeyIdentifier: record.identifier ?: name });
                [self showError:WKLocalized(@"addons.error.installTitle") message:cause.localizedDescription?:WKLocalized(@"addons.error.importMessage")];
                [self updateToolbar];
                return;
            }
            TKAddonHubLog(TKAddonHubEventRow, @{ TKAddonHubKeyOutcome: @"installed",
                TKAddonHubKeyProvider: TKAddonProvenanceAPI,
                TKAddonHubKeyIdentifier: record.identifier ?: name });
            self.browseStatus=compatibility==TKCurseForgeCompatibilityVerified
                ? WKLocalizedFormat(@"addons.installedStatus",name)
                : WKLocalizedFormat(@"addons.installedUnverified",name);
            [self reloadAddons];
            [self checkForUpdates];
        });
    }];
    [task resume];
}
- (void)reloadAddons {
    [NSFileManager.defaultManager createDirectoryAtPath:_addOnsDirectory withIntermediateDirectories:YES attributes:nil error:NULL];
    [_store reload]; _addons=TKWoWAddonsAtDirectory(_addOnsDirectory);
    // A package that went away cannot stay selected, and a state for it is meaningless.
    NSMutableSet<NSString *> *live=[NSMutableSet new];
    for (TKAddonRecord *record in _store.records) if (record.identifier) [live addObject:record.identifier];
    [_selected intersectSet:live];
    NSMutableSet<NSString *> *liveKeys=[NSMutableSet new];
    for (TKAddonRecord *record in _store.records) {
        NSString *key=record.uuid ?: record.identifier;
        if (key) [liveKeys addObject:key];
        [self restoreRecordedUpdateState:record];
    }
    for (NSString *key in [_updateAnswers.allKeys copy]) if (![liveKeys containsObject:key]) [_updateAnswers removeObjectForKey:key];
    for (NSString *key in [_updateFailures.allKeys copy]) if (![liveKeys containsObject:key]) [_updateFailures removeObjectForKey:key];
    for (NSString *key in [_updateResults.allKeys copy]) if (![liveKeys containsObject:key]) [_updateResults removeObjectForKey:key];
    [_downloadingPackages intersectSet:liveKeys];
    for (TKAddonRecord *record in _store.records) {
        NSString *key=record.uuid ?: record.identifier;
        if (key) _updateResults[key]=@([self updateResultForRecord:record]);
    }
    [self.tableView reloadData];
    [self updateToolbar];
}

#pragma mark - The bundled WolkaraRoue package

// The package this app ships, located and verified. The app's verifier is Swift and the
// fixture does not link it, so it is found by name exactly as the store finds the archive
// extractor; a fixture supplies the same shape through `bundledPackageProvider` instead.
- (nullable NSDictionary *)loadBundledPackage:(NSError **)error {
    Class packageClass=NSClassFromString(@"TKAddonPackage");
    SEL selector=NSSelectorFromString(@"bundledPackageWithError:");
    if (!packageClass || ![packageClass respondsToSelector:selector]) {
        if (error) *error=[NSError errorWithDomain:@"WolkaraForever.AddOns" code:2
            userInfo:@{NSLocalizedDescriptionKey:WKLocalized(@"addons.bundled.unavailable")}];
        return nil;
    }
    NSMethodSignature *signature=[packageClass methodSignatureForSelector:selector];
    NSInvocation *invocation=[NSInvocation invocationWithMethodSignature:signature];
    invocation.target=packageClass; invocation.selector=selector;
    NSError *__autoreleasing localError=nil;
    NSError *__autoreleasing *pointer=&localError;
    [invocation setArgument:&pointer atIndex:2];
    [invocation invoke];
    __unsafe_unretained NSDictionary *result=nil;
    [invocation getReturnValue:&result];
    if (error) *error=localError;
    return result;
}
- (void)reloadBundledPackage {
    NSError *error=nil;
    NSDictionary *package=nil;
    if (self.bundledPackageProvider) package=self.bundledPackageProvider(&error);
    else package=[self loadBundledPackage:&error];
    _bundledPackage=package;
    _bundledPackageError=error;
    if (self.isViewLoaded) [self.tableView reloadData];
}
// The record this store already owns for the bundled folder, if any. It is what makes a
// second Install an Update of the same package instead of a second copy of it.
- (nullable TKAddonRecord *)bundledRecord {
    for (TKAddonRecord *record in _store.records)
        if ([record.folders containsObject:@"WolkaraRoue"]) return record;
    return nil;
}
// Explicit, and transactional: the store stages the archive, validates it, copies it under
// the update lock and commits the manifest, and a failure leaves the game's AddOns folder and
// the manifest exactly where they were. Nothing is installed by opening the page.
- (void)installBundledPackage {
    if (_bundledInstalling) return;
    NSURL *archive=[_bundledPackage[@"archive"] isKindOfClass:NSURL.class]?_bundledPackage[@"archive"]:nil;
    NSString *release=[_bundledPackage[@"release"] isKindOfClass:NSString.class]?_bundledPackage[@"release"]:nil;
    if (!archive || !release.length) {
        [self showError:WKLocalized(@"addons.bundled.title")
                message:_bundledPackageError.localizedDescription?:WKLocalized(@"addons.bundled.unavailable")];
        return;
    }
    _bundledInstalling=YES; [self.tableView reloadData];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
        NSError *error=nil;
        TKAddonRecord *existing=[self bundledRecord];
        BOOL ok=existing
            ? [self.store updateRecord:existing archiveURL:archive provider:nil
                            provenance:TKAddonProvenanceFiles error:&error]
            : [self.store importZIPAtURL:archive provider:nil
                              provenance:TKAddonProvenanceFiles error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.bundledInstalling=NO;
            if (!ok) {
                [self showError:WKLocalized(@"addons.error.installTitle")
                        message:error.localizedDescription?:WKLocalized(@"addons.error.importMessage")];
                [self.tableView reloadData];
                return;
            }
            self.browseStatus=WKLocalizedFormat(@"addons.bundled.installed",release);
            [self reloadAddons];
            [self checkForUpdates];
        });
    });
}

#pragma mark - Update detection, selection and bulk update

- (nullable TKAddonRecord *)recordForIdentifier:(NSString *)identifier {
    for (TKAddonRecord *record in _store.records) if ([record.identifier isEqual:identifier]) return record;
    return nil;
}
- (BOOL)recordIsSelectable:(TKAddonRecord *)record {
    return record.managed && !record.disabled;
}

// What the row says about this package's update. Every caller - the row, the bulk run, the
// toolbar's count, the fixture - asks this one question, so none of them can drift apart.
- (TKAddonUpdateResult)updateResultForRecord:(TKAddonRecord *)record {
    NSString *key=record.uuid ?: record.identifier;
    TKAddonUpdateFacts *facts=[TKAddonUpdateFacts new];
    facts.heldBack=record.disabled || record.pinned;
    facts.linked=record.linked;
    facts.checking=[_checkingPackages containsObject:key];
    facts.downloading=[_downloadingPackages containsObject:key];
    // Nothing has answered and nothing is in flight: the row's honest answer is "not checked
    // yet", and its action is to ask.
    facts.pending=!_updateAnswers[key] && !_updateFailures[key] &&
        !facts.checking && !facts.downloading;
    NSString *failure=_updateFailures[key];
    facts.failedRetryable=[failure isEqual:@"retryable"];
    facts.failedTerminal=[failure isEqual:@"terminal"];
    NSDictionary *answer=_updateAnswers[key];
    facts.answered=answer!=nil;
    facts.newerFileExists=[answer[@"newer"] boolValue];
    facts.installedFileIsCurrent=[answer[@"current"] boolValue];
    facts.noCompatibleFile=[answer[@"none"] boolValue];
    // A project the API will not hand archives to can still be reached in the app when this
    // build knows its own page. That is the difference between "needs browser confirmation" and
    // "unavailable", and it is decided from recorded facts, not from a failed request.
    facts.apiArchiveAvailable=[answer[@"api"] boolValue];
    facts.browserRoutable=[self browserPageAvailableForRecord:record];
    return TKAddonUpdateResolve(facts);
}

- (BOOL)browserPageAvailableForRecord:(TKAddonRecord *)record {
    NSString *slug=record.provider[TKAddonProviderProjectSlug];
    if (![slug isKindOfClass:NSString.class] || !slug.length) return NO;
    TKAddonBrowserHandoff *handoff=[TKAddonBrowserHandoff new];
    handoff.projectID=record.provider[TKAddonProviderProjectID] ?: @0;
    handoff.projectSlug=slug;
    return [handoff projectURL]!=nil;
}

// The resolver's result in the table view's own vocabulary. Kept in one switch so a new resolver
// state cannot be silently drawn as something else.
- (TKAddonUpdateState)stateForRecord:(TKAddonRecord *)record {
    switch ([self updateResultForRecord:record]) {
        case TKAddonUpdateResultNotApplicable: return TKAddonUpdateStateNotUpdatable;
        case TKAddonUpdateResultUpToDate: return TKAddonUpdateStateUpToDate;
        case TKAddonUpdateResultUpdateAvailable: return TKAddonUpdateStateAvailable;
        case TKAddonUpdateResultChecking:
        case TKAddonUpdateResultDownloading: return TKAddonUpdateStateBusy;
        case TKAddonUpdateResultNeedsBrowserConfirmation: return TKAddonUpdateStateBrowser;
        case TKAddonUpdateResultUnlinked: return TKAddonUpdateStateUnlinked;
        case TKAddonUpdateResultUnavailableNoCompatibleFile: return TKAddonUpdateStateUnavailable;
        case TKAddonUpdateResultFailedRetryable: return TKAddonUpdateStateFailed;
        case TKAddonUpdateResultFailedTerminal: return TKAddonUpdateStateTerminal;
        // Never asked. Its own row state, so the row offers the check instead of claiming one.
        case TKAddonUpdateResultNotChecked: return TKAddonUpdateStateNotChecked;
    }
    return TKAddonUpdateStateUnknown;
}
- (BOOL)recordHasUpdateAvailable:(TKAddonRecord *)record {
    return [self updateResultForRecord:record]==TKAddonUpdateResultUpdateAvailable;
}

// Seed a row's word from what the last check recorded, so a relaunch shows the answer it already
// had instead of claiming to be checking again. Nothing here authorizes anything: it is a word
// on a row, and the next check replaces it.
- (void)restoreRecordedUpdateState:(TKAddonRecord *)record {
    NSString *key=record.uuid ?: record.identifier;
    NSString *stored=record.lastUpdateState;
    if (!stored.length) return;
    TKAddonUpdateResult result=TKAddonUpdateResultForStoredValue(stored);
    switch (result) {
        case TKAddonUpdateResultUpdateAvailable:
            _updateAnswers[key]=@{ @"newer": @YES, @"api": @YES }; break;
        case TKAddonUpdateResultNeedsBrowserConfirmation:
            _updateAnswers[key]=@{ @"newer": @YES, @"api": @NO }; break;
        case TKAddonUpdateResultUpToDate:
            _updateAnswers[key]=@{ @"current": @YES }; break;
        case TKAddonUpdateResultUnavailableNoCompatibleFile:
            _updateAnswers[key]=@{ @"none": @YES }; break;
        case TKAddonUpdateResultFailedRetryable:
            _updateFailures[key]=@"retryable"; break;
        case TKAddonUpdateResultFailedTerminal:
            _updateFailures[key]=@"terminal"; break;
        default: break;
    }
    _updateResults[key]=@([self updateResultForRecord:record]);
}

// Commit what a check concluded for the packages it touched, in one manifest write.
- (void)persistUpdateStates {
    NSMutableDictionary<NSString *, NSString *> *states=[NSMutableDictionary dictionary];
    for (TKAddonRecord *record in _store.records) {
        NSString *key=record.uuid ?: record.identifier;
        if (!key) continue;
        if (!_updateAnswers[key] && !_updateFailures[key]) continue;
        NSString *stored=TKAddonUpdateStoredValue([self updateResultForRecord:record]);
        if (stored) states[key]=stored;
    }
    if (states.count) [_store setUpdateStates:states checkedAt:[self nowStamp] error:NULL];
}

- (NSString *)nowStamp {
    static NSISO8601DateFormatter *formatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ formatter=[NSISO8601DateFormatter new]; });
    return [formatter stringFromDate:NSDate.date];
}

// Ask the provider what it currently has for every package that could be updated, then compare
// file identity. Version strings are not compared: two uploads can carry the same display
// version, and a package's own version string is whatever its TOC says.
- (void)checkForUpdates {
    if (_checkingUpdates) return;
    // Every record gets a route decision first, including the ones that will not be asked
    // about: an unlinked package is a named state, not an empty one.
    for (TKAddonRecord *record in _store.records) {
        [self restoreRecordedUpdateState:record];
        NSString *key=record.uuid ?: record.identifier;
        if (!key) continue;
        _updateResults[key]=@([self updateResultForRecord:record]);
    }
    NSString *key=[_credentials curseForgeKey:NULL];
    if (!key.length) {
        // No key: the sweep cannot ask anything, so every linked package keeps its honest
        // answer - "Not checked yet" with a Check action - instead of being left on the word
        // "Checking…" that nothing is backing up. This is what the installed list showed on
        // 2026-11-13 when the row state and the work had drifted apart.
        TKAddonHubLog(TKAddonHubEventUpdate, @{ TKAddonHubKeyOutcome: @"skipped",
            TKAddonHubKeyReason: @"no-api-key" });
        for (TKAddonRecord *record in _store.records) {
            [_checkingPackages removeObject:record.uuid ?: record.identifier];
        }
        _checkingUpdates=NO;
        _updateQueue=nil;
        _updateClient=nil;
        [self.tableView reloadData];
        [self updateToolbar];
        return;
    }
    NSMutableArray<TKAddonRecord *> *candidates=[NSMutableArray new];
    for (TKAddonRecord *record in _store.records) {
        if (!record.managed || record.disabled) continue;
        if (!record.linked) { [self setAnswer:@{ } forRecord:record]; continue; }
        if (record.pinned) { [self setAnswer:@{ } forRecord:record]; continue; }
        [candidates addObject:record];
        [self setAnswer:@{ } forRecord:record];
    }
    if (!candidates.count) { [self.tableView reloadData]; return; }
    _checkingUpdates=YES;
    _updateQueue=candidates;
    _updateClient=[[TKCurseForgeClient alloc] initWithAPIKey:key];
    _updateGeneration+=1;
    TKAddonHubLog(TKAddonHubEventUpdate, @{ TKAddonHubKeyOutcome: @"queued",
        TKAddonHubKeyCount: @(candidates.count) });
    [self checkNextUpdate];
}

- (void)setAnswer:(NSDictionary *)answer forRecord:(TKAddonRecord *)record {
    NSString *key=record.uuid ?: record.identifier;
    if (!key) return;
    if (answer.count) _updateAnswers[key]=answer; else [_updateAnswers removeObjectForKey:key];
    [_updateFailures removeObjectForKey:key];
    _updateResults[key]=@([self updateResultForRecord:record]);
}

// One package at a time, deliberately: a metadata sweep across a dozen packages should not open
// a dozen connections to a rate-limited API at once. Written as a method rather than a recursive
// block so the queue cannot keep itself alive.
- (void)checkNextUpdate {
    if (!_checkingUpdates) return;
    if (!_updateQueue.count) {
        _checkingUpdates=NO;
        _updateQueue=nil;
        _updateClient=nil;
        [_checkingPackages removeAllObjects];
        [self persistUpdateStates];
        [self.tableView reloadData];
        [self updateToolbar];
        return;
    }
    TKAddonRecord *record=_updateQueue.firstObject;
    [_updateQueue removeObjectAtIndex:0];
    NSNumber *projectID=record.provider[TKAddonProviderProjectID];
    NSNumber *currentFile=record.provider[TKAddonProviderFileID];
    NSString *recordKey=record.uuid ?: record.identifier;
    [_checkingPackages addObject:recordKey];
    NSUInteger generation=_updateGeneration;
    TKCurseForgeClient *client=_updateClient;
    __weak TKWoWAddonManagerViewController *weakSelf=self;
    [client bestFileForModID:projectID gameVersion:TKForeverGameVersion completion:^(TKCurseForgeFileCandidate *candidate,NSError *error){
        dispatch_async(dispatch_get_main_queue(), ^{
            TKWoWAddonManagerViewController *self=weakSelf;
            if (!self) return;
            if (generation != self->_updateGeneration) { self->_checkingUpdates=NO; return; }
            [self.checkingPackages removeObject:recordKey];
            if (error) {
                // A rejected key or a missing project will not fix itself; a network or a rate
                // limit will. Saying which is the difference between a Retry that helps and one
                // that repeats the same refusal.
                BOOL retryable=!(error.code==401 || error.code==403 || error.code==404);
                self.updateFailures[recordKey]=retryable?@"retryable":@"terminal";
                [self.updateAnswers removeObjectForKey:recordKey];
            } else if (!candidate) {
                self.updateAnswers[recordKey]=@{ @"none": @YES };
                [self.updateFailures removeObjectForKey:recordKey];
            } else {
                NSNumber *newest=candidate.file[@"id"];
                BOOL current=[newest isKindOfClass:NSNumber.class] && [newest isEqual:currentFile];
                // `downloadUrl` present, or an API answer that is not a 403, is what makes the
                // archive obtainable here. A file the API lists without a URL is the project
                // saying "not through the API", which is the browser's job.
                NSString *carried=[candidate.file[@"downloadUrl"] isKindOfClass:NSString.class]
                    ? candidate.file[@"downloadUrl"] : nil;
                self.updateAnswers[recordKey]=@{ @"newer": @(!current), @"current": @(current),
                                                 @"api": @(carried.length>0) };
                [self.updateFailures removeObjectForKey:recordKey];
                if (!current && carried.length && [candidate.file isKindOfClass:NSDictionary.class])
                    self.updateCandidates[recordKey]=candidate.file;
                else [self.updateCandidates removeObjectForKey:recordKey];
            }
            self.updateResults[recordKey]=@([self updateResultForRecord:record]);
            TKAddonHubLog(TKAddonHubEventUpdate, @{ TKAddonHubKeyOutcome: @"checked",
                TKAddonHubKeyIdentifier: record.identifier,
                TKAddonHubKeyState: TKAddonUpdateStoredValue([self updateResultForRecord:record]) ?: @"checking" });
            [self.tableView reloadData];
            [self checkNextUpdate];
        });
    }];
}

- (void)updateRecord:(TKAddonRecord *)record completion:(void (^)(BOOL ok, NSError *error))completion {
    [self updateRecord:record allowBrowser:YES completion:completion];
}

// Start a source-appropriate update. A project whose archive the API will not hand out is not a
// failure: the action becomes the in-app page, and the row returns to the same place afterwards.
- (void)updateRecord:(TKAddonRecord *)record allowBrowser:(BOOL)allowBrowser
          completion:(void (^)(BOOL ok, NSError *error))completion {
    NSString *key=record.uuid ?: record.identifier;
    if (!record.linked) {
        if (completion) completion(NO, [NSError errorWithDomain:@"WolkaraForever.AddOns" code:1 userInfo:@{NSLocalizedDescriptionKey:WKLocalized(@"addons.update.noProvider")}]);
        return;
    }
    NSString *apiKey=[_credentials curseForgeKey:NULL];
    TKAddonUpdateResult current=[self updateResultForRecord:record];
    if (current==TKAddonUpdateResultNeedsBrowserConfirmation) {
        if (allowBrowser) { [self openBrowserForRecord:record]; if (completion) completion(YES, nil); }
        else if (completion) completion(NO, [NSError errorWithDomain:@"WolkaraForever.AddOns" code:2 userInfo:@{NSLocalizedDescriptionKey:WKLocalized(@"addons.update.needsBrowser")}]);
        return;
    }
    if (!apiKey.length) { [self setupKey]; if (completion) completion(NO, nil); return; }
    NSNumber *projectID=record.provider[TKAddonProviderProjectID];
    NSNumber *currentFile=record.provider[TKAddonProviderFileID];
    [_updateFailures removeObjectForKey:key];
    [_downloadingPackages addObject:key];
    _updateResults[key]=@([self updateResultForRecord:record]);
    [self.tableView reloadData];
    [self updateToolbar];
    TKCurseForgeClient *client=[[TKCurseForgeClient alloc] initWithAPIKey:apiKey];
    NSDictionary *project=@{ @"id": projectID, @"name": record.name ?: record.identifier };
    __weak TKWoWAddonManagerViewController *weakSelf=self;
    [client bestFileForModID:projectID gameVersion:TKForeverGameVersion completion:^(TKCurseForgeFileCandidate *candidate,NSError *error){
        dispatch_async(dispatch_get_main_queue(), ^{
            TKWoWAddonManagerViewController *self=weakSelf;
            if (!self) return;
            if (error || !candidate) {
                [self.downloadingPackages removeObject:key];
                self.updateFailures[key]=@"retryable";
                self.updateResults[key]=@([self updateResultForRecord:record]);
                [self.tableView reloadData];
                [self updateToolbar];
                if (completion) completion(NO, error);
                return;
            }
            NSNumber *newest=candidate.file[@"id"];
            if ([newest isKindOfClass:NSNumber.class] && [newest isEqual:currentFile]) {
                // The provider already has what is installed. Saying so is the honest answer,
                // and it is the answer that keeps the row from offering the same file again.
                [self.downloadingPackages removeObject:key];
                self.updateAnswers[key]=@{ @"current": @YES };
                [self.updateFailures removeObjectForKey:key];
                self.updateResults[key]=@([self updateResultForRecord:record]);
                [self.tableView reloadData];
                [self updateToolbar];
                if (completion) completion(YES, nil);
                return;
            }
            NSString *carried=[candidate.file[@"downloadUrl"] isKindOfClass:NSString.class]?candidate.file[@"downloadUrl"]:nil;
            if (!carried.length && allowBrowser) {
                // The API listed a newer file but will not hand it over. Nothing failed; this
                // update belongs to the page, so the row states that and opens it.
                [self.downloadingPackages removeObject:key];
                self.updateAnswers[key]=@{ @"newer": @YES, @"api": @NO };
                self.updateResults[key]=@([self updateResultForRecord:record]);
                [self.tableView reloadData];
                [self updateToolbar];
                [self openBrowserForRecord:record];
                if (completion) completion(YES, nil);
                return;
            }
            [self installCandidate:candidate project:project replacing:record client:client
                              name:record.name ?: record.identifier];
            if (completion) completion(YES, nil);
        });
    }];
}

// A package the bulk run should try: one the provider has a newer file for, whether the API can
// hand it over or only the project's own page can. A browser-confirmation package is *not*
// dropped from the plan - it is queued, reported, and opened when the player asks.
- (BOOL)recordIsBulkEligible:(TKAddonRecord *)record {
    TKAddonUpdateResult result=[self updateResultForRecord:record];
    return result==TKAddonUpdateResultUpdateAvailable || result==TKAddonUpdateResultNeedsBrowserConfirmation;
}
- (NSArray<TKAddonRecord *> *)selectedUpdatableRecords {
    NSMutableArray<TKAddonRecord *> *records=[NSMutableArray new];
    for (TKAddonRecord *record in _store.records)
        if ([_selected containsObject:record.identifier] && [self recordIsBulkEligible:record]) [records addObject:record];
    return records;
}
- (NSArray<TKAddonRecord *> *)allUpdatableRecords {
    NSMutableArray<TKAddonRecord *> *records=[NSMutableArray new];
    for (TKAddonRecord *record in _store.records) if ([self recordIsBulkEligible:record]) [records addObject:record];
    return records;
}

- (void)setSelectedIdentifier:(NSString *)identifier selected:(BOOL)selected {
    if (!identifier.length) return;
    if (selected) [_selected addObject:identifier]; else [_selected removeObject:identifier];
    [self.tableView reloadData];
    [self updateNavigationItems];
}
- (void)selectAll {
    for (TKAddonRecord *record in _store.records) if ([self recordIsSelectable:record]) [_selected addObject:record.identifier];
    [self.tableView reloadData];
    [self updateNavigationItems];
}
- (void)clearSelection {
    [_selected removeAllObjects];
    [self.tableView reloadData];
    [self updateNavigationItems];
}

// The one confirmation every multi-package mutation goes through. It says how many packages and
// which ones, because "update 4 add-ons" is not something a person should have to take on trust.
- (void)confirmBulkUpdate:(NSArray<TKAddonRecord *> *)records title:(NSString *)title verb:(NSString *)verb {
    if (!records.count) {
        [self showError:WKLocalized(@"addons.error.changeTitle") message:WKLocalized(@"addons.update.none")];
        return;
    }
    NSMutableArray<NSString *> *names=[NSMutableArray new];
    for (TKAddonRecord *record in records) [names addObject:record.name ?: record.identifier];
    NSString *list=[names componentsJoinedByString:@"\n• "];
    UIAlertController *sheet=[UIAlertController alertControllerWithTitle:title
        message:WKLocalizedFormat(@"addons.update.confirm", list)
        preferredStyle:UIAlertControllerStyleActionSheet];
    __weak TKWoWAddonManagerViewController *weakSelf=self;
    [sheet addAction:[UIAlertAction actionWithTitle:verb style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        (void)action; [weakSelf runBulkUpdate:records];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:WKLocalized(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
    [self presentSheet:sheet from:nil];
}

- (void)runBulkUpdate:(NSArray<TKAddonRecord *> *)records {
    if (!records.count || self.bulkUpdating) return;
    self.bulkUpdating=YES;
    _bulkCancelled=NO;
    _bulkNeedsBrowser=0;
    _bulkQueue=[records mutableCopy];
    _bulkFailures=0;
    TKAddonHubLog(TKAddonHubEventUpdate, @{ TKAddonHubKeyOutcome: @"bulk",
        TKAddonHubKeyAction: @"started", TKAddonHubKeyCount: @(records.count) });
    [self updateNavigationItems];
    [self runNextBulkUpdate];
}

// The player's own stop. Whatever has been committed stays committed; nothing is rolled back on
// their behalf, and the packages after the current one are simply not started.
- (void)cancelBulkUpdate {
    if (!self.bulkUpdating) return;
    _bulkCancelled=YES;
    TKAddonHubLog(TKAddonHubEventCancel, @{ TKAddonHubKeyOutcome: @"cancelled",
        TKAddonHubKeyAction: @"bulk", TKAddonHubKeyCount: @(_bulkQueue.count) });
    self.bulkStatus=WKLocalized(@"addons.update.cancelled");
    [self updateNavigationItems];
}

// One package at a time, so a failure in the middle leaves the packages after it untouched and
// still attempted. A method rather than a recursive block: the block form kept the queue alive
// through its own capture.
- (void)runNextBulkUpdate {
    if (_bulkCancelled || !_bulkQueue.count) {
        // Partial failure is reported by package and does not stop the packages after it.
        self.bulkUpdating=NO;
        self.bulkStatus=nil;
        NSUInteger failed=_bulkFailures;
        NSUInteger browser=_bulkNeedsBrowser;
        _bulkQueue=nil; _bulkFailures=0; _bulkNeedsBrowser=0;
        [self updateNavigationItems];
        [self reloadAddons];
        TKAddonHubLog(TKAddonHubEventUpdate, @{ TKAddonHubKeyOutcome: _bulkCancelled?@"cancelled":@"finished",
            TKAddonHubKeyCount: @(failed), TKAddonHubKeyReason: browser?@"browser-queued":@"done" });
        if (browser) {
            // Named rather than silent: these are the ones whose archive only the project's own
            // page can hand over. Nothing was dropped and nothing failed.
            [self showError:WKLocalized(@"addons.update.allTitle")
                    message:WKLocalizedFormat(@"addons.update.browserQueued",(unsigned long)browser)];
        }
        if (failed) [self showError:WKLocalized(@"addons.error.changeTitle")
                            message:WKLocalizedFormat(@"addons.update.partialFailure",(unsigned long)failed)];
        return;
    }
    TKAddonRecord *record=_bulkQueue.firstObject;
    [_bulkQueue removeObjectAtIndex:0];
    self.bulkStatus=WKLocalizedFormat(@"addons.update.working", record.name ?: record.identifier);
    [self updateNavigationItems];
    // A browser-confirmation package is counted and skipped here: opening a modal page in the
    // middle of a serialized run would interrupt the run and hide the package after it.
    if ([self updateResultForRecord:record]==TKAddonUpdateResultNeedsBrowserConfirmation) {
        _bulkNeedsBrowser+=1;
        [self runNextBulkUpdate];
        return;
    }
    __weak TKWoWAddonManagerViewController *weakSelf=self;
    [self updateRecord:record allowBrowser:NO completion:^(BOOL ok, NSError *error){
        (void)error;
        TKWoWAddonManagerViewController *self=weakSelf;
        if (!self) return;
        if (!ok) self->_bulkFailures+=1;
        TKAddonHubLog(TKAddonHubEventRow, @{ TKAddonHubKeyOutcome: ok?@"updated":@"failed",
            TKAddonHubKeyIdentifier: record.identifier, TKAddonHubKeyAction: @"update-all" });
        [self runNextBulkUpdate];
    }];
}

- (void)updateNavigationItems { [self updateToolbar]; }
- (void)tappedUpdateSelected {
    if (self.bulkUpdating) { [self cancelBulkUpdate]; return; }
    [self confirmBulkUpdate:[self selectedUpdatableRecords]
                      title:WKLocalized(@"addons.update.selectedTitle")
                       verb:WKLocalized(@"addons.select.updateSelected")];
}
- (void)tappedUpdateAll {
    if (self.bulkUpdating) { [self cancelBulkUpdate]; return; }
    [self confirmBulkUpdate:[self allUpdatableRecords]
                      title:WKLocalized(@"addons.update.allTitle")
                       verb:WKLocalized(@"addons.updateAll")];
}

- (void)importAddon {
    UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeZIP] asCopy:YES];
    picker.allowsMultipleSelection=NO; picker.delegate=self;
    [self presentViewController:picker animated:YES completion:nil];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    (void)controller;
    NSError *failure=nil; NSURL *url=urls.firstObject; BOOL accessed=[url startAccessingSecurityScopedResource];
    if (!url || ![_store importZIPAtURL:url provider:nil provenance:TKAddonProvenanceFiles error:&failure]) { }
    if (accessed) [url stopAccessingSecurityScopedResource];
    TKAddonHubLog(TKAddonHubEventArchive, @{ TKAddonHubKeyOutcome: failure?@"failed":@"imported",
        TKAddonHubKeyProvider: TKAddonProvenanceFiles, TKAddonHubKeyAction: @"files" });
    [self reloadAddons];
    [self checkForUpdates];
    if (failure) {
        // The document picker is still dismissing on this callback. Queue the
        // alert so an import failure is never hidden behind that transition.
        dispatch_async(dispatch_get_main_queue(), ^{
            UIAlertController *alert=[UIAlertController alertControllerWithTitle:WKLocalized(@"addons.error.importTitle") message:failure.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:WKLocalized(@"common.ok") style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        });
    }
}
// MARK: - My Add-ons: what the list draws

// The sort orders the toolbar offers. They change the order of the same records and nothing else.
static NSString *TKAddonInstalledSortKey(NSInteger sort) {
    switch (sort) {
        case 1: return @"addons.myaddons.sort.version";
        case 2: return @"addons.myaddons.sort.update";
        default: return @"addons.myaddons.sort.name";
    }
}
static NSString *TKAddonInstalledFilterKey(NSInteger filter) {
    switch (filter) {
        case 1: return @"addons.myaddons.filter.enabled";
        case 2: return @"addons.myaddons.filter.disabled";
        case 3: return @"addons.myaddons.filter.updatable";
        case 4: return @"addons.myaddons.filter.unlinked";
        default: return @"addons.myaddons.filter.all";
    }
}
- (NSString *)installedSortKey { return TKAddonInstalledSortKey(_installedSort); }
- (NSString *)installedFilterKey { return TKAddonInstalledFilterKey(_installedFilter); }

// The records My Add-ons currently draws. Search, filter and sort are applied here and nowhere
// else, so a control that changes none of them changes nothing.
- (NSArray<TKAddonRecord *> *)visibleRecords {
    NSString *query=[_installedQuery stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSMutableArray<TKAddonRecord *> *records=[NSMutableArray array];
    for (TKAddonRecord *record in _store.records) {
        switch (_installedFilter) {
            case 1: if (record.disabled) continue; break;
            case 2: if (!record.disabled) continue; break;
            case 3: {
                TKAddonUpdateResult result=[self updateResultForRecord:record];
                if (result!=TKAddonUpdateResultUpdateAvailable &&
                    result!=TKAddonUpdateResultNeedsBrowserConfirmation) continue;
                break;
            }
            case 4: if (record.linked) continue; break;
            default: break;
        }
        if (query.length) {
            NSString *haystack=[@[record.name ?: @"", record.author ?: @"", record.identifier ?: @""]
                componentsJoinedByString:@"\n"];
            if ([haystack rangeOfString:query options:NSCaseInsensitiveSearch].location==NSNotFound) continue;
        }
        [records addObject:record];
    }
    [records sortUsingComparator:^NSComparisonResult(TKAddonRecord *a, TKAddonRecord *b) {
        switch (self->_installedSort) {
            case 1: {
                NSComparisonResult order=[(a.version ?: @"") localizedStandardCompare:(b.version ?: @"")];
                if (order!=NSOrderedSame) return order;
                break;
            }
            case 2: {
                // Packages with something to do come first, then everything else, each in name
                // order. Only the word the row already shows decides the place.
                BOOL aAction=TKAddonUpdateIsActionable([self updateResultForRecord:a]);
                BOOL bAction=TKAddonUpdateIsActionable([self updateResultForRecord:b]);
                if (aAction!=bAction) return aAction?NSOrderedAscending:NSOrderedDescending;
                break;
            }
            default: break;
        }
        return [(a.name ?: a.identifier ?: @"") localizedCaseInsensitiveCompare:(b.name ?: b.identifier ?: @"")];
    }];
    return records;
}

// The My Add-ons sections: the summary row, then one section per group, then whatever is in no
// group. A group with no member is not drawn - an empty heading is a control that did nothing.
- (NSArray<NSDictionary *> *)myAddOnSections {
    NSArray<TKAddonRecord *> *visible=[self visibleRecords];
    NSMutableArray<NSDictionary *> *sections=[NSMutableArray array];
    NSMutableArray *summary=[NSMutableArray array];
    [summary addObject:@{ @"kind": @"summary" }];
    if (_recommendation==TKAddonRecommendationWolkaraRoue) [summary addObject:@{ @"kind": @"bundled" }];
    // The explanatory line only when there is something to explain: an empty list already says
    // it is empty one row above. A dictionary literal cannot carry nil, so the footer is added
    // only when there is one.
    NSMutableDictionary *summarySection = [@{ @"kind": @"summary", @"rows": summary } mutableCopy];
    if (_store.records.count) summarySection[@"footer"] = WKLocalized(@"addons.installed.footer");
    [sections addObject:summarySection];
    NSMutableSet<NSString *> *grouped=[NSMutableSet new];
    for (TKAddonGroup *group in _store.groups) {
        NSMutableArray<TKAddonRecord *> *rows=[NSMutableArray array];
        for (TKAddonRecord *record in visible)
            if (record.uuid && [group.members containsObject:record.uuid]) {
                [rows addObject:record];
                [grouped addObject:record.uuid];
            }
        if (!rows.count) continue;
        [sections addObject:@{ @"kind": @"group", @"rows": rows, @"title": group.name, @"group": group }];
    }
    NSMutableArray<TKAddonRecord *> *loose=[NSMutableArray array];
    for (TKAddonRecord *record in visible)
        if (!record.uuid || ![grouped containsObject:record.uuid]) [loose addObject:record];
    if (loose.count)
        [sections addObject:@{ @"kind": @"group", @"rows": loose,
            @"title": _store.groups.count?WKLocalized(@"addons.group.ungrouped"):WKLocalized(@"addons.installed") }];
    return sections;
}

- (NSArray<NSDictionary *> *)sectionsForCurrentTab {
    switch (_tab) {
        case TKAddonHubTabDiscover:
            // A tab that draws nothing is a tab that looks broken. With no key, or with an
            // answer that has no projects, Discover says which state it is in.
            if (_discoverSections.count) return _discoverSections;
            return @[ @{ @"kind": @"message",
                         @"rows": @[_discoverStatus ?: WKLocalized(@"addons.discover.empty")] } ];
        case TKAddonHubTabBrowse:
            // Without a key there is one row to read and one thing to do; the sort and filter
            // controls would be two more copies of the same sentence, so they wait for a key.
            return @[
                @{ @"kind": @"browseControls", @"rows": [self hasKey] ? @[ @0, @1 ] : @[ @0 ] },
                @{ @"kind": @"browseResults", @"rows": _results },
            ];
        case TKAddonHubTabMyAddOns:
        default: return [self myAddOnSections];
    }
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return (NSInteger)[self sectionsForCurrentTab].count;
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    NSArray<NSDictionary *> *sections=[self sectionsForCurrentTab];
    if (section<0 || section>=(NSInteger)sections.count) return 0;
    NSDictionary *entry=sections[section];
    NSString *kind=entry[@"kind"];
    if ([kind isEqual:@"browseResults"]) return (NSInteger)_results.count + ([self canLoadMore]?1:0);
    return (NSInteger)[entry[@"rows"] count];
}
// Whether a given section is the Browse results, whatever index it has: the bundled
// recommendation section sits above them, so the header that names the columns cannot be the
// second section by position any more.
- (BOOL)sectionIsBrowseResults:(NSInteger)section {
    NSArray<NSDictionary *> *sections=[self sectionsForCurrentTab];
    if (section<0 || section>=(NSInteger)sections.count) return NO;
    return [sections[section][@"kind"] isEqual:@"browseResults"];
}
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    (void)tableView;
    if ([self sectionIsBrowseResults:section] && _results.count) {
        TKAddonColumnsHeaderView *header=[[TKAddonColumnsHeaderView alloc] initWithFrame:CGRectMake(0,0,tableView.bounds.size.width,22)];
        [header configureWithColumns:_columns compact:TKAddonRowsAreCompact(self.tableView.bounds.size.width)];
        return header;
    }
    return nil;
}
- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    (void)tableView;
    if ([self sectionIsBrowseResults:section] && _results.count) return 22;
    return UITableViewAutomaticDimension;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    NSArray<NSDictionary *> *sections=[self sectionsForCurrentTab];
    if (section<0 || section>=(NSInteger)sections.count) return nil;
    NSString *title=sections[section][@"title"];
    return [title isKindOfClass:NSString.class] && title.length ? title : nil;
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    NSArray<NSDictionary *> *sections=[self sectionsForCurrentTab];
    if (section<0 || section>=(NSInteger)sections.count) return nil;
    NSDictionary *entry=sections[section];
    // The access row already says what to do; repeating it underneath is the same sentence twice
    // on one page. Once a key is there, this is where "no matches" is said.
    if ([entry[@"kind"] isEqual:@"browseResults"]) return [self hasKey] ? _browseStatus : nil;
    NSString *footer=entry[@"footer"];
    return [footer isKindOfClass:NSString.class] ? footer : nil;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"addon"];
    if (!cell) cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"addon"];
    cell.selectionStyle=UITableViewCellSelectionStyleDefault;
    NSArray<NSDictionary *> *sections=[self sectionsForCurrentTab];
    if (indexPath.section<0 || indexPath.section>=(NSInteger)sections.count) return cell;
    NSDictionary *entry=sections[indexPath.section];
    NSString *kind=entry[@"kind"];

    if ([kind isEqual:@"browseControls"]) {
        if (![self hasKey]) { cell.textLabel.text=WKLocalized(@"addons.setUpAccess"); cell.detailTextLabel.text=WKLocalized(@"addons.setUpAccess.detail"); }
        else if (indexPath.row==0) { cell.textLabel.text=WKLocalizedFormat(@"addons.sort.current",BrowseSortLabel(_sortField)); cell.detailTextLabel.text=WKLocalizedFormat(@"addons.sort.tapToChange",[_sortOrder isEqual:@"asc"]?WKLocalized(@"addons.sort.ascending"):WKLocalized(@"addons.sort.descending")); }
        else { cell.textLabel.text=WKLocalizedFormat(@"addons.filters.category",_categoryLabel?:WKLocalized(@"addons.filters.allCategories")); cell.detailTextLabel.text=WKLocalized(@"addons.filters.tapToFilter"); }
    } else if ([kind isEqual:@"browseResults"] || [kind isEqual:@"discover"]) {
        NSArray<NSDictionary *> *projects=[kind isEqual:@"discover"] ? entry[@"rows"] : _results;
        if ([kind isEqual:@"browseResults"] && indexPath.row==(NSInteger)_results.count) {
            cell.textLabel.text=WKLocalized(@"addons.loadMore");
            cell.detailTextLabel.text=WKLocalizedFormat(@"addons.projectsOfShown",(unsigned long)_results.count,(unsigned long)_totalCount);
        } else {
            TKAddonProjectCell *project=[tableView dequeueReusableCellWithIdentifier:@"project"];
            if (!project) project=[[TKAddonProjectCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"project"];
            NSDictionary *projectEntry=projects[indexPath.row];
            TKCurseForgeFileCandidate *candidate=TKAddonCandidate(projectEntry,_gameVersion);
            NSDictionary *file=candidate.file;
            NSNumber *modID=[projectEntry[@"id"] isKindOfClass:NSNumber.class]?projectEntry[@"id"]:nil;
            project.accessibilityIdentifier=modID?[NSString stringWithFormat:@"wow.addons.project.%@",modID]:@"wow.addons.project";
            NSString *rank=[projectEntry[@"gamePopularityRank"] isKindOfClass:NSNumber.class]?
                [NSString stringWithFormat:@"%@",projectEntry[@"gamePopularityRank"]]:nil;
            BOOL distribution = ![projectEntry[@"allowModDistribution"] isKindOfClass:NSNumber.class] || [projectEntry[@"allowModDistribution"] boolValue];
            TKAddonInstallState state=TKAddonInstallStateIdle;
            if (modID && [_installing containsObject:modID]) state=TKAddonInstallStateBusy;
            else if ([self installedRecordForProjectID:modID]) state=TKAddonInstallStateInstalled;
            // A project the API will not distribute is not "unavailable": its page is the
            // acquisition route, so the row's action says so and opens it in the app.
            else if (!distribution) state=TKAddonInstallStateBrowser;
            __weak TKWoWAddonManagerViewController *weakSelf=self;
            project.onInstall=^{
                TKWoWAddonManagerViewController *self=weakSelf;
                if (!self) return;
                if (!distribution) { [self openBrowserForProjectEntry:projectEntry]; return; }
                [self installMod:projectEntry];
            };
            [project configureWithProject:projectEntry file:file rank:rank columns:_columns gameVersion:_gameVersion
                                   compact:TKAddonRowsAreCompact(self.tableView.bounds.size.width)
                              installState:state];
            return project;
        }
    } else if ([kind isEqual:@"message"]) {
        // A tab with nothing to list still says why. One row, no action, no spinner: the state
        // is the sentence, and Refresh is what changes it.
        NSArray *messageRows=entry[@"rows"];
        cell.textLabel.text=[messageRows.firstObject isKindOfClass:NSString.class]?messageRows.firstObject:nil;
        cell.detailTextLabel.text=WKLocalized(@"addons.discover.hint");
        cell.selectionStyle=UITableViewCellSelectionStyleNone;
        cell.accessibilityIdentifier=@"wow.addons.discover.state";
    } else if ([kind isEqual:@"bundled"]) {
        // The launcher's own package, as a row with its own explicit Install action. It is the
        // only installed package this page draws: installing it is still a press, never a
        // consequence of opening the page.
        TKAddonBundledCell *bundled=[tableView dequeueReusableCellWithIdentifier:@"bundled"];
        if (!bundled) bundled=[[TKAddonBundledCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"bundled"];
        bundled.accessibilityIdentifier=@"wow.addons.bundled";
        __weak TKWoWAddonManagerViewController *weakSelf=self;
        bundled.onInstall=^{ [weakSelf installBundledPackage]; };
        [bundled configureWithPackage:_bundledPackage error:_bundledPackageError
                                 busy:_bundledInstalling installed:[self bundledRecord]!=nil];
        return bundled;
    } else if ([kind isEqual:@"summary"]) {
        NSDictionary *row=entry[@"rows"][indexPath.row];
        if ([row[@"kind"] isEqual:@"bundled"]) {
            TKAddonBundledCell *bundled=[tableView dequeueReusableCellWithIdentifier:@"bundled"];
            if (!bundled) bundled=[[TKAddonBundledCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"bundled"];
            bundled.accessibilityIdentifier=@"wow.addons.bundled";
            __weak TKWoWAddonManagerViewController *weakSelf=self;
            bundled.onInstall=^{ [weakSelf installBundledPackage]; };
            [bundled configureWithPackage:_bundledPackage error:_bundledPackageError
                                     busy:_bundledInstalling installed:[self bundledRecord]!=nil];
            return bundled;
        }
        cell.textLabel.text=_addons.count?WKLocalizedCountFormat(@"addons.count",(NSInteger)_addons.count,(unsigned long)_addons.count):WKLocalized(@"addons.count.none");
        cell.detailTextLabel.text=nil; cell.selectionStyle=UITableViewCellSelectionStyleNone;
    } else {
        // An installed package is its own row: a checkbox, the package as a person reads it, the
        // one word about its update, and the action that goes with that word.
        TKAddonInstalledCell *installed=[tableView dequeueReusableCellWithIdentifier:@"installed"];
        if (!installed) installed=[[TKAddonInstalledCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"installed"];
        TKAddonRecord *addon=entry[@"rows"][indexPath.row];
        __weak TKWoWAddonManagerViewController *weakSelf=self;
        NSString *identifier=addon.identifier;
        TKAddonRecord *target=addon;
        installed.onToggleSelection=^(BOOL selected){
            [weakSelf setSelectedIdentifier:identifier selected:selected];
        };
        installed.onUpdate=^{
            TKWoWAddonManagerViewController *self=weakSelf; if(!self) return;
            [self startRowActionForRecord:target];
        };
        installed.onManage=^{
            TKWoWAddonManagerViewController *self=weakSelf; if(!self) return;
            [self presentSheet:[self manageSheetForRecord:target] from:indexPath];
        };
        installed.onBrowser=^{
            TKWoWAddonManagerViewController *self=weakSelf; if(!self) return;
            [self openBrowserForRecord:target];
        };
        installed.onLink=^{
            TKWoWAddonManagerViewController *self=weakSelf; if(!self) return;
            [self presentLinkSheetForRecord:target from:indexPath];
        };
        [installed configureWithRecord:addon
                              selected:[_selected containsObject:identifier]
                            selectable:[self recordIsSelectable:addon]
                                 state:[self stateForRecord:addon]
                                detail:[self detailForRecord:addon]];
        return installed;
    }
    cell.backgroundColor=[UIColor colorWithRed:0.07 green:0.09 blue:0.13 alpha:1]; cell.textLabel.textColor=[UIColor colorWithRed:0.9 green:0.72 blue:0.35 alpha:1]; cell.detailTextLabel.textColor=[UIColor colorWithWhite:0.75 alpha:1]; cell.textLabel.numberOfLines=0; cell.detailTextLabel.numberOfLines=0;
    return cell;
}
// The line under an installed package's name: version, author, whether it is managed, whether it
// is pinned, and - when the TOC does not declare Forever's interface - that it is unverified.
// The acquisition route is *not* here: it is diagnostic detail, and a row that changed its
// controls by route would make an API package different from a Files package. It is in the
// detail sheet's activity line instead.
- (NSString *)detailForRecord:(TKAddonRecord *)addon {
    NSString *state=addon.disabled?WKLocalized(@"addons.state.disabled"):(addon.managed?WKLocalized(@"addons.state.managed"):WKLocalized(@"addons.state.unverified"));
    NSMutableArray<NSString *> *parts=[NSMutableArray array];
    if (addon.version.length) [parts addObject:addon.version];
    if (addon.author.length) [parts addObject:addon.author];
    [parts addObject:state];
    if (addon.pinned) [parts addObject:WKLocalized(@"addons.state.pinnedShort")];
    if ([addon.compatibility isEqual:TKAddonCompatibilityUnverified] && !addon.disabled)
        [parts addObject:WKLocalized(@"addons.state.notVerifiedForForever")];
    return [parts componentsJoinedByString:@" · "];
}
- (nullable TKAddonRecord *)installedRecordForProjectID:(NSNumber *)projectID {
    if (!projectID) return nil;
    for (TKAddonRecord *record in _store.records) {
        if (!record.managed || !record.linked) continue;
        if ([record.provider[TKAddonProviderProjectID] isEqual:projectID]) return record;
    }
    return nil;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSArray<NSDictionary *> *sections=[self sectionsForCurrentTab];
    if (indexPath.section<0 || indexPath.section>=(NSInteger)sections.count) return;
    NSDictionary *entry=sections[indexPath.section];
    NSString *kind=entry[@"kind"];
    if ([kind isEqual:@"summary"] || [kind isEqual:@"bundled"]) return;
    if ([kind isEqual:@"browseResults"]) {
        if (indexPath.row==(NSInteger)_results.count) { [self loadMore]; return; }
        [self presentProject:_results[indexPath.row]]; return;
    }
    if ([kind isEqual:@"discover"]) { [self presentProject:entry[@"rows"][indexPath.row]]; return; }
    TKAddonRecord *record=entry[@"rows"][indexPath.row];
    [self presentDetailForRecord:record from:indexPath];
}
// The actions a managed package offers, built in one place so the page and the device self-test
// exercise the same sheet. The destructive action is what removes a package, and it is here
// rather than only in the row's tap handler because "can I delete anything?" is a question a
// test has to be able to answer without a second pair of hands on the iPad.
- (UIAlertController *)manageSheetForRecord:(TKAddonRecord *)record {
    // The sheet's body is the package's own activity: which route it arrived by, when it was
    // installed, and when it was last checked. The route is *diagnostic* - it is here and not on
    // the row, because a row whose controls changed by route would make one package different
    // from another for no reason the player can act on.
    NSMutableArray<NSString *> *activity=[NSMutableArray array];
    [activity addObject:WKLocalizedFormat(@"addons.detail.route", TKAddonSourceName(record.provenance))];
    if (record.installedAt.length) [activity addObject:WKLocalizedFormat(@"addons.detail.installed", record.installedAt)];
    if (record.lastCheckedAt.length) [activity addObject:WKLocalizedFormat(@"addons.detail.checked", record.lastCheckedAt)];
    [activity addObject:WKLocalized(TKAddonUpdateTitleKey([self updateResultForRecord:record]))];
    NSString *activityText=[activity componentsJoinedByString:@"\n"];
    UIAlertController *sheet=[UIAlertController alertControllerWithTitle:record.name
        message:record.disabled?WKLocalized(@"addons.manage.disabledNote"):activityText
        preferredStyle:UIAlertControllerStyleActionSheet];
    UIAlertAction *cancel=[UIAlertAction actionWithTitle:WKLocalized(@"common.cancel") style:UIAlertActionStyleCancel handler:nil];
    if (!record.managed) {
        sheet.message=[NSString stringWithFormat:@"%@\n%@", WKLocalized(@"addons.manage.unmanaged"), activityText];
        // A folder this store did not install still gets every local action. The two that need an
        // owning record - disable and pin - are absent; the ones that manage the folder and the
        // package's identity are all here.
        TKAddonUpdateResult result=[self updateResultForRecord:record];
        if (TKAddonUpdateIsActionable(result)) {
            [sheet addAction:[UIAlertAction actionWithTitle:WKLocalized(@"addons.action.update") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){(void)a;[self startRowActionForRecord:record];}]];
        }
        [sheet addAction:[UIAlertAction actionWithTitle:record.linked?WKLocalized(@"addons.link.remove"):WKLocalized(@"addons.link.title") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){(void)a;[self presentLinkSheetForRecord:record from:nil];}]];
        if (_store.groups.count)
            [sheet addAction:[UIAlertAction actionWithTitle:WKLocalized(@"addons.group.title") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){(void)a;[self presentGroupSheetForRecord:record from:nil];}]];
        [sheet addAction:[UIAlertAction actionWithTitle:WKLocalized(@"addons.remove") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a){(void)a;[self mutate:^BOOL(NSError **e){return [self.store removeRecord:record error:e];}];}]];
        [sheet addAction:cancel];
        return sheet;
    }
    if (TKAddonUpdateIsActionable([self updateResultForRecord:record]))
        [sheet addAction:[UIAlertAction actionWithTitle:WKLocalized(@"addons.action.update") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){(void)a;[self startRowActionForRecord:record];}]];
    [sheet addAction:[UIAlertAction actionWithTitle:record.disabled?WKLocalized(@"addons.restore"):WKLocalized(@"addons.disable") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){(void)a;[self mutate:^BOOL(NSError **e){return [self.store setDisabled:!record.disabled record:record error:e];}];}]];
    // Pinning is how a user says "leave this one alone". It is honoured by every update path,
    // not only by the row that offers it.
    [sheet addAction:[UIAlertAction actionWithTitle:record.pinned?WKLocalized(@"addons.unpin"):WKLocalized(@"addons.pin") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){(void)a;[self mutate:^BOOL(NSError **e){return [self.store setPinned:!record.pinned record:record error:e];}];}]];
    [sheet addAction:[UIAlertAction actionWithTitle:record.linked?WKLocalized(@"addons.link.remove"):WKLocalized(@"addons.link.title") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){(void)a;[self presentLinkSheetForRecord:record from:nil];}]];
    if (_store.groups.count)
        [sheet addAction:[UIAlertAction actionWithTitle:WKLocalized(@"addons.group.title") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){(void)a;[self presentGroupSheetForRecord:record from:nil];}]];
    [sheet addAction:[UIAlertAction actionWithTitle:WKLocalized(@"addons.remove") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a){(void)a;[self mutate:^BOOL(NSError **e){return [self.store removeRecord:record error:e];}];}]];
    [sheet addAction:cancel];
    return sheet;
}
// One place that shows an alert, so every one of them is bounded the same way.
- (void)presentAlert:(UIAlertController *)alert {
    WKPreparePopupForPresentation(alert, self.view);
    WKPresentWhenFree(self, ^{
        [self presentViewController:alert animated:YES completion:^{
            WKConstrainPopupToScreen(alert, self.view);
        }];
    });
}
- (void)showProviderError:(NSError *)error { dispatch_async(dispatch_get_main_queue(),^{UIAlertController *a=[UIAlertController alertControllerWithTitle:WKLocalized(@"addons.error.providerTitle") message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:WKLocalized(@"common.ok") style:UIAlertActionStyleDefault handler:nil]];[self presentAlert:a];}); }
- (void)mutate:(BOOL (^)(NSError **))operation { NSError *error=nil; if(!operation(&error)){UIAlertController *a=[UIAlertController alertControllerWithTitle:WKLocalized(@"addons.error.changeTitle") message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:WKLocalized(@"common.ok") style:UIAlertActionStyleDefault handler:nil]];[self presentAlert:a];} [self reloadAddons]; [self checkForUpdates]; }
- (void)setupKey { UIAlertController *a=[UIAlertController alertControllerWithTitle:WKLocalized(@"addons.key.title") message:WKLocalized(@"addons.key.message") preferredStyle:UIAlertControllerStyleAlert];[a addTextFieldWithConfigurationHandler:^(UITextField *f){f.secureTextEntry=YES;f.autocorrectionType=UITextAutocorrectionTypeNo;f.autocapitalizationType=UITextAutocapitalizationTypeNone;f.placeholder=WKLocalized(@"addons.key.placeholder");}];[a addAction:[UIAlertAction actionWithTitle:WKLocalized(@"addons.key.save") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){(void)x;NSError *e=nil;if(![self.credentials storeCurseForgeKey:a.textFields.firstObject.text error:&e]){UIAlertController *failure=[UIAlertController alertControllerWithTitle:WKLocalized(@"addons.key.errorTitle") message:e.localizedDescription preferredStyle:UIAlertControllerStyleAlert];[failure addAction:[UIAlertAction actionWithTitle:WKLocalized(@"common.ok") style:UIAlertActionStyleDefault handler:nil]];[self presentAlert:failure];}else { [self.tableView reloadData]; if (self.tab==TKAddonHubTabBrowse) [self beginBrowse]; else [self checkForUpdates]; }}]];[a addAction:[UIAlertAction actionWithTitle:WKLocalized(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];[self presentAlert:a]; }

#pragma mark - My Add-ons controls

- (UIMenu *)installedSortMenu {
    __weak TKWoWAddonManagerViewController *weakSelf=self;
    NSMutableArray<UIMenuElement *> *actions=[NSMutableArray array];
    for (NSInteger option=0;option<3;option++) {
        NSInteger chosen=option;
        UIAction *action=[UIAction actionWithTitle:WKLocalized(TKAddonInstalledSortKey(option)) image:nil
                                          identifier:nil handler:^(UIAction *a) {
            (void)a; TKWoWAddonManagerViewController *self=weakSelf; if(!self)return;
            self.installedSort=chosen;
            [self updateToolbar]; [self.tableView reloadData];
        }];
        action.state=option==_installedSort?UIMenuElementStateOn:UIMenuElementStateOff;
        [actions addObject:action];
    }
    return [UIMenu menuWithTitle:WKLocalized(@"addons.myaddons.sort") children:actions];
}
- (UIMenu *)installedFilterMenu {
    __weak TKWoWAddonManagerViewController *weakSelf=self;
    NSMutableArray<UIMenuElement *> *actions=[NSMutableArray array];
    for (NSInteger option=0;option<5;option++) {
        NSInteger chosen=option;
        UIAction *action=[UIAction actionWithTitle:WKLocalized(TKAddonInstalledFilterKey(option)) image:nil
                                          identifier:nil handler:^(UIAction *a) {
            (void)a; TKWoWAddonManagerViewController *self=weakSelf; if(!self)return;
            self.installedFilter=chosen;
            [self updateToolbar]; [self.tableView reloadData];
        }];
        action.state=option==_installedFilter?UIMenuElementStateOn:UIMenuElementStateOff;
        [actions addObject:action];
    }
    return [UIMenu menuWithTitle:WKLocalized(@"addons.myaddons.filter") children:actions];
}

// Create a local group. It changes no file and gives no package a new identity; it only changes
// which heading the row appears under.
- (void)tappedCreateGroup {
    UIAlertController *sheet=[UIAlertController alertControllerWithTitle:WKLocalized(@"addons.group.create")
                                                                 message:WKLocalized(@"addons.group.message")
                                                          preferredStyle:UIAlertControllerStyleAlert];
    [sheet addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder=WKLocalized(@"addons.group.placeholder");
        field.autocapitalizationType=UITextAutocapitalizationTypeWords;
        field.accessibilityIdentifier=@"wow.addons.group.name";
    }];
    __weak TKWoWAddonManagerViewController *weakSelf=self;
    [sheet addAction:[UIAlertAction actionWithTitle:WKLocalized(@"addons.group.create") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        (void)action;
        TKWoWAddonManagerViewController *self=weakSelf; if(!self) return;
        NSError *error=nil;
        if (![self.store createGroupNamed:sheet.textFields.firstObject.text error:&error]) {
            [self showError:WKLocalized(@"addons.error.changeTitle") message:error.localizedDescription];
            return;
        }
        [self reloadAddons];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:WKLocalized(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
    [self presentAlert:sheet];
}

// Group membership for one package. Joining or leaving moves nothing on disk.
- (void)presentGroupSheetForRecord:(TKAddonRecord *)record from:(NSIndexPath *)indexPath {
    if (!_store.groups.count) {
        [self showError:WKLocalized(@"addons.group.title") message:WKLocalized(@"addons.group.none")];
        return;
    }
    UIAlertController *sheet=[UIAlertController alertControllerWithTitle:record.name
                                                                 message:WKLocalized(@"addons.group.membership")
                                                          preferredStyle:UIAlertControllerStyleActionSheet];
    __weak TKWoWAddonManagerViewController *weakSelf=self;
    for (TKAddonGroup *group in _store.groups) {
        BOOL member=[group.members containsObject:record.uuid ?: @""];
        [sheet addAction:[UIAlertAction actionWithTitle:member?[@"✓ " stringByAppendingString:group.name]:group.name
                                                 style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            (void)action;
            TKWoWAddonManagerViewController *self=weakSelf; if(!self) return;
            NSError *error=nil;
            if (![self.store setGroup:group member:record joined:!member error:&error])
                [self showError:WKLocalized(@"addons.error.changeTitle") message:error.localizedDescription];
            [self reloadAddons];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:WKLocalized(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
    [self presentSheet:sheet from:indexPath];
}

// One row's action, chosen by the resolver's answer and nothing else.
- (void)startRowActionForRecord:(TKAddonRecord *)record {
    TKAddonUpdateResult result=[self updateResultForRecord:record];
    TKAddonHubLog(TKAddonHubEventRow, @{ TKAddonHubKeyOutcome: @"action",
        TKAddonHubKeyIdentifier: record.identifier,
        TKAddonHubKeyAction: TKAddonUpdateStoredValue(result) ?: @"checking",
        TKAddonHubKeyProvider: record.provenance });
    switch (result) {
        case TKAddonUpdateResultNeedsBrowserConfirmation:
            [self openBrowserForRecord:record];
            return;
        case TKAddonUpdateResultUnlinked:
            [self presentLinkSheetForRecord:record from:nil];
            return;
        case TKAddonUpdateResultNotChecked: {
            // The check this row has never had. Without a key there is nothing to ask, so the
            // key prompt is the action - and the rows then say "Not checked yet" instead of
            // pretending a request is running.
            if (![self hasKey]) { [self setupKey]; return; }
            [self checkForUpdates];
            return;
        }
        case TKAddonUpdateResultChecking:
            // Already being asked. Nested before the default so a second tap does not queue a
            // second sweep behind the first.
            return;
        case TKAddonUpdateResultDownloading:
            // The only cancel that means anything: the archive is in flight and nothing has
            // been committed yet.
            [_downloadingPackages removeObject:record.uuid ?: record.identifier];
            _updateResults[record.uuid ?: record.identifier]=@([self updateResultForRecord:record]);
            TKAddonHubLog(TKAddonHubEventCancel, @{ TKAddonHubKeyOutcome: @"cancelled",
                TKAddonHubKeyIdentifier: record.identifier, TKAddonHubKeyAction: @"row" });
            [self.tableView reloadData];
            return;
        case TKAddonUpdateResultFailedTerminal:
            [self presentSheet:[self manageSheetForRecord:record] from:nil];
            return;
        default:
            break;
    }
    __weak TKWoWAddonManagerViewController *weakSelf=self;
    [self updateRecord:record completion:^(BOOL ok, NSError *error){
        (void)error;
        TKWoWAddonManagerViewController *self=weakSelf; if(!self) return;
        [self checkForUpdates];
        if (!ok) (void)self;
    }];
}

// MARK: - In-app browser

- (void)openBrowserForProjectEntry:(NSDictionary *)entry {
    NSNumber *projectID=[entry[@"id"] isKindOfClass:NSNumber.class]?entry[@"id"]:nil;
    if (!projectID) return;
    TKAddonBrowserHandoff *handoff=[TKAddonBrowserHandoff new];
    handoff.projectID=projectID;
    handoff.projectName=[entry[@"name"] isKindOfClass:NSString.class]?entry[@"name"]:nil;
    handoff.projectSlug=[self projectSlugForEntry:entry];
    if (!handoff.projectSlug.length) {
        [self showError:WKLocalized(@"addons.error.installTitle") message:WKLocalized(@"addons.browser.noPage")];
        return;
    }
    [self presentHandoff:handoff forRecord:[self installedRecordForProjectID:projectID]];
}

- (void)openBrowserForRecord:(TKAddonRecord *)record {
    NSNumber *projectID=record.provider[TKAddonProviderProjectID];
    NSString *slug=record.provider[TKAddonProviderProjectSlug];
    if (![projectID isKindOfClass:NSNumber.class] || !slug.length) {
        [self showError:WKLocalized(@"addons.error.installTitle") message:WKLocalized(@"addons.browser.noPage")];
        return;
    }
    TKAddonBrowserHandoff *handoff=[TKAddonBrowserHandoff new];
    handoff.projectID=projectID;
    handoff.fileID=[record.provider[TKAddonProviderFileID] isKindOfClass:NSNumber.class]?record.provider[TKAddonProviderFileID]:nil;
    handoff.projectName=record.name;
    handoff.projectSlug=slug;
    handoff.releaseName=record.provider[TKAddonProviderVersion];
    [self presentHandoff:handoff forRecord:record];
}

// The browser is acquisition, so what it hands back is installed under the identity the action
// named - never under whatever the page happened to be showing when the ZIP arrived.
- (void)presentHandoff:(TKAddonBrowserHandoff *)handoff forRecord:(nullable TKAddonRecord *)record {
    TKWoWAddonBrowserViewController *browser=[[TKWoWAddonBrowserViewController alloc] initWithHandoff:handoff];
    UINavigationController *navigation=[[UINavigationController alloc] initWithRootViewController:browser];
    WKPreparePopupForPresentation(navigation, self.view);
    navigation.modalPresentationStyle=UIModalPresentationFormSheet;
    __weak TKWoWAddonManagerViewController *weakSelf=self;
    __weak TKWoWAddonBrowserViewController *weakBrowser=browser;
    browser.onDownload=^(NSURL *archive) {
        TKWoWAddonManagerViewController *self=weakSelf;
        TKWoWAddonBrowserViewController *browser=weakBrowser;
        if (!self) return;
        [browser dismissViewControllerAnimated:YES completion:^{
            [self installBrowserArchive:archive handoff:handoff replacing:record];
        }];
    };
    browser.onCancel=^(NSString *reasonKey) {
        TKWoWAddonManagerViewController *self=weakSelf;
        TKWoWAddonBrowserViewController *browser=weakBrowser;
        if (!self) return;
        [browser dismissViewControllerAnimated:YES completion:^{
            if (![reasonKey isEqual:@"addons.browser.cancelled"])
                [self showError:WKLocalized(@"addons.browser.title") message:WKLocalized(reasonKey)];
            TKAddonHubLog(TKAddonHubEventHandoff, @{ TKAddonHubKeyOutcome: @"closed",
                TKAddonHubKeyIdentifier: handoff.projectSlug, TKAddonHubKeyAction: @"browser" });
            [self reloadAddons];
        }];
    };
    // Through the page's own presentation funnel: this is opened from a page sheet, and on
    // 2026-11-12 opening it while that sheet was still arriving produced UIKit's "unbalanced
    // calls to begin/end appearance transitions". The funnel now waits for a transition to end
    // before it presents anything.
    __weak TKWoWAddonManagerViewController *weakPresenter=self;
    WKPresentWhenFree(self, ^{
        TKWoWAddonManagerViewController *self=weakPresenter;
        if (!self) return;
        [self presentViewController:navigation animated:YES completion:^{
            WKConstrainPopupToScreen(navigation, self.view);
        }];
    });
}
- (void)installBrowserArchive:(NSURL *)archive handoff:(TKAddonBrowserHandoff *)handoff
                    replacing:(nullable TKAddonRecord *)record {
    NSDictionary *provider=@{ TKAddonProviderKind: @"curseforge",
        TKAddonProviderProjectID: handoff.projectID,
        TKAddonProviderProjectSlug: handoff.projectSlug ?: @"",
        TKAddonProviderProjectName: handoff.projectName ?: @"",
        TKAddonProviderFileID: handoff.fileID ?: @0,
        TKAddonProviderVersion: handoff.releaseName ?: @"",
        TKAddonProviderCompatibility: TKAddonCompatibilityUnverified };
    NSError *error=nil;
    BOOL ok=NO;
    if (record) ok=[_store updateRecord:record archiveURL:archive provider:provider
                             provenance:TKAddonProvenanceBrowser error:&error];
    else ok=[_store importZIPAtURL:archive provider:provider
                        provenance:TKAddonProvenanceBrowser error:&error];
    // The temporary download directory is ours and holds the only copy; nothing else may keep it.
    [[NSFileManager defaultManager] removeItemAtURL:archive.URLByDeletingLastPathComponent error:NULL];
    if (!ok) {
        TKAddonHubLog(TKAddonHubEventHandoff, @{ TKAddonHubKeyOutcome: @"failed",
            TKAddonHubKeyIdentifier: handoff.projectSlug, TKAddonHubKeyReason: @"install" });
        [self showError:WKLocalized(@"addons.error.installTitle")
                message:error.localizedDescription ?: WKLocalized(@"addons.error.importMessage")];
        [self reloadAddons];
        return;
    }
    TKAddonHubLog(TKAddonHubEventHandoff, @{ TKAddonHubKeyOutcome: @"installed",
        TKAddonHubKeyIdentifier: handoff.projectSlug, TKAddonHubKeyAction: @"browser" });
    [self reloadAddons];
    [self checkForUpdates];
}

// MARK: - Detail and linking

- (void)presentDetailForRecord:(TKAddonRecord *)record from:(NSIndexPath *)indexPath {
    UIAlertController *sheet=[self manageSheetForRecord:record];
    [self presentSheet:sheet from:indexPath];
}

// The sheet a package's own "Link project" action opens. It records the project the player names
// and nothing else: no folder is moved, no version is assumed, and no update is guessed from the
// package's name. Until this is done the package is fully managed locally and simply excluded
// from provider updates.
- (void)presentLinkSheetForRecord:(TKAddonRecord *)record from:(NSIndexPath *)indexPath {
    UIAlertController *sheet=[UIAlertController alertControllerWithTitle:WKLocalized(@"addons.link.title")
                                                                 message:WKLocalized(@"addons.link.message")
                                                          preferredStyle:UIAlertControllerStyleActionSheet];
    __weak TKWoWAddonManagerViewController *weakSelf=self;
    if (record.linked || record.provider) {
        [sheet addAction:[UIAlertAction actionWithTitle:WKLocalized(@"addons.link.remove") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            (void)action;
            TKWoWAddonManagerViewController *self=weakSelf; if(!self) return;
            NSError *error=nil;
            if (![self.store unlinkRecord:record error:&error])
                [self showError:WKLocalized(@"addons.error.changeTitle") message:error.localizedDescription];
            [self reloadAddons];
            [self checkForUpdates];
        }]];
    }
    // Searching by the package's own name is offered as a starting point and nothing more: the
    // player chooses the project, so the identity comes from their choice.
    [sheet addAction:[UIAlertAction actionWithTitle:WKLocalized(@"addons.link.search") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        (void)action;
        TKWoWAddonManagerViewController *self=weakSelf; if(!self) return;
        [self presentLinkSearchForRecord:record];
    }]];
    NSString *linkedSlug=record.provider[TKAddonProviderProjectSlug];
    if ([linkedSlug isKindOfClass:NSString.class] && linkedSlug.length)
        [sheet addAction:[UIAlertAction actionWithTitle:WKLocalized(@"addons.link.open") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            (void)action; [weakSelf openBrowserForRecord:record];
        }]];
    [sheet addAction:[UIAlertAction actionWithTitle:WKLocalized(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
    [self presentSheet:sheet from:indexPath];
}

- (void)presentLinkSearchForRecord:(TKAddonRecord *)record {
    NSString *key=[_credentials curseForgeKey:NULL];
    if (!key.length) { [self setupKey]; return; }
    TKCurseForgeClient *client=[[TKCurseForgeClient alloc] initWithAPIKey:key];
    __weak TKWoWAddonManagerViewController *weakSelf=self;
    [client browseModsWithQuery:record.name ?: record.identifier sortField:TKCurseForgeDefaultSortField()
                      sortOrder:@"desc" categoryID:nil gameVersion:nil classID:nil index:0
                     completion:^(id value,NSError *error){
        dispatch_async(dispatch_get_main_queue(), ^{
            TKWoWAddonManagerViewController *self=weakSelf; if(!self) return;
            if (error) { [self showError:WKLocalized(@"addons.error.providerTitle") message:error.localizedDescription]; return; }
            NSArray *projects=[value[@"data"] isKindOfClass:NSArray.class]?value[@"data"]:@[];
            if (!projects.count) { [self showError:WKLocalized(@"addons.link.title") message:WKLocalized(@"addons.link.noResults")]; return; }
            UIAlertController *sheet=[UIAlertController alertControllerWithTitle:WKLocalized(@"addons.link.choose")
                                                                         message:WKLocalized(@"addons.link.message")
                                                                  preferredStyle:UIAlertControllerStyleActionSheet];
            NSUInteger shown=0;
            for (NSDictionary *project in projects) {
                if (![project isKindOfClass:NSDictionary.class] || shown>=8) break;
                NSNumber *projectID=[project[@"id"] isKindOfClass:NSNumber.class]?project[@"id"]:nil;
                NSString *name=[project[@"name"] isKindOfClass:NSString.class]?project[@"name"]:nil;
                NSString *slug=[self projectSlugForEntry:project];
                if (!projectID || !name.length || !slug.length) continue;
                shown+=1;
                [sheet addAction:[UIAlertAction actionWithTitle:name style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                    (void)action;
                    TKWoWAddonManagerViewController *self=weakSelf; if(!self) return;
                    NSDictionary *provider=@{ TKAddonProviderKind: @"curseforge",
                        TKAddonProviderProjectID: projectID, TKAddonProviderProjectSlug: slug,
                        TKAddonProviderProjectName: name };
                    NSError *linkError=nil;
                    if (![self.store linkRecord:record provider:provider
                                     provenance:record.provenance error:&linkError])
                        [self showError:WKLocalized(@"addons.error.changeTitle") message:linkError.localizedDescription];
                    [self reloadAddons];
                    [self checkForUpdates];
                }]];
            }
            if (!shown) { [self showError:WKLocalized(@"addons.link.title") message:WKLocalized(@"addons.link.noResults")]; return; }
            [sheet addAction:[UIAlertAction actionWithTitle:WKLocalized(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
            [self presentSheet:sheet from:nil];
        });
    }];
}

// MARK: - Discover

// Discover is the native catalog: featured, latest and popular, as the API answers them. With no
// key it is a named empty state, never a browser page.
- (void)fetchDiscover {
    if (_discoverLoading) return;
    NSString *key=[_credentials curseForgeKey:NULL];
    if (!key.length) {
        _discoverSections=@[];
        _discoverStatus=WKLocalized(@"addons.enterKey.long");
        [self.tableView reloadData];
        [self updateToolbar];
        return;
    }
    _discoverLoading=YES;
    _discoverStatus=WKLocalized(@"addons.loading");
    [self.tableView reloadData];
    [self updateToolbar];
    TKCurseForgeClient *client=[[TKCurseForgeClient alloc] initWithAPIKey:key];
    __weak TKWoWAddonManagerViewController *weakSelf=self;
    // Three lists, each one request, run in parallel and drawn together: a section that arrives
    // on its own would move the page under the player's finger.
    dispatch_group_t group=dispatch_group_create();
    NSMutableArray<NSArray *> *lists=[@[@[],@[],@[]] mutableCopy];
    NSArray<TKCurseForgeSortField *> *fields=TKCurseForgeSortFields();
    for (NSUInteger index=0;index<3;index++) {
        NSInteger field=index<fields.count?fields[index].wireValue:TKCurseForgeDefaultSortField();
        dispatch_group_enter(group);
        [client browseModsWithQuery:@"" sortField:field sortOrder:@"desc" categoryID:nil
                        gameVersion:TKForeverGameVersion classID:nil index:0
                         completion:^(id value,NSError *error){
            (void)error;
            NSArray *projects=[value[@"data"] isKindOfClass:NSArray.class]?value[@"data"]:@[];
            @synchronized (lists) { lists[index]=projects; }
            dispatch_group_leave(group);
        }];
    }
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        TKWoWAddonManagerViewController *self=weakSelf; if(!self) return;
        self.discoverLoading=NO;
        NSArray<NSString *> *titles=@[ WKLocalized(@"addons.discover.featured"),
                                       WKLocalized(@"addons.discover.latest"),
                                       WKLocalized(@"addons.discover.popular") ];
        NSMutableArray<NSDictionary *> *sections=[NSMutableArray array];
        NSUInteger total=0;
        for (NSUInteger index=0;index<3;index++) {
            NSArray *projects=lists[index];
            total+=projects.count;
            if (!projects.count) continue;
            [sections addObject:@{ @"kind": @"discover", @"title": titles[index], @"rows": projects }];
        }
        self.discoverSections=sections;
        self.discoverStatus=total?WKLocalizedFormat(@"addons.projectsFound",
            [NSString stringWithFormat:@"%lu",(unsigned long)total]):WKLocalized(@"addons.discover.empty");
        [self.tableView reloadData];
        [self updateToolbar];
    });
}
@end
