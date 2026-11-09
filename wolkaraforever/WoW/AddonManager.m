#import "AddonManager.h"
#import "AddonStore.h"
#import "AddonCredentialStore.h"
#import "CurseForgeClient.h"
#import "../App/WKLocalization.h"
#import "../App/WolkaraForeverTheme.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static NSString *const TKForeverGameVersion=@"1.60.1";

// A record's source as a person reads it. The stored word is contract - the store writes it, the
// package files carry it, and the log repeats it - so only the words beside it are translated. An
// unknown one is shown as it came rather than as a key.
static NSString *TKAddonSourceName(NSString *source) {
    if ([source isEqual:@"Existing"]) return WKLocalized(@"addons.source.existing");
    if ([source isEqual:@"WolkaraForever import"]) return WKLocalized(@"addons.source.import");
    if ([source isEqual:@"zip"]) return WKLocalized(@"addons.source.zip");
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

// What the installed list knows about one package's update.
typedef NS_ENUM(NSInteger, TKAddonUpdateState) {
    // No provider identity, or pinned, or disabled: nothing to compare and nothing to offer.
    TKAddonUpdateStateNotUpdatable = 0,
    // Metadata has not been fetched for this package yet.
    TKAddonUpdateStateUnknown,
    TKAddonUpdateStateUpToDate,
    TKAddonUpdateStateAvailable,
    TKAddonUpdateStateBusy,
    TKAddonUpdateStateFailed,
};

// One installed package: a checkbox, the package as a person reads it, and - only when there
// really is a newer file this app could install - an Update action.
@interface TKAddonInstalledCell : UITableViewCell
@property (nonatomic, copy, nullable) void (^onToggleSelection)(BOOL selected);
@property (nonatomic, copy, nullable) void (^onUpdate)(void);
@property (nonatomic, copy, nullable) void (^onManage)(void);
@property (nonatomic, readonly) UIButton *checkbox;
@property (nonatomic, readonly) UIButton *updateButton;
- (void)configureWithRecord:(TKAddonRecord *)record selected:(BOOL)selected
                   selectable:(BOOL)selectable state:(TKAddonUpdateState)state
                       detail:(NSString *)detail;
@end

@implementation TKAddonInstalledCell {
    UIButton *_checkbox;
    UILabel *_titleLabel, *_detailLabel;
    UIButton *_updateButton;
    BOOL _showsManage;
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
        UIStackView *text=[[UIStackView alloc] initWithArrangedSubviews:@[_titleLabel,_detailLabel]];
        text.axis=UILayoutConstraintAxisVertical; text.spacing=2;
        [text setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
        _updateButton=[UIButton buttonWithType:UIButtonTypeSystem];
        _updateButton.titleLabel.font=[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        _updateButton.tintColor=WKGold();
        _updateButton.contentHorizontalAlignment=UIControlContentHorizontalAlignmentRight;
        [_updateButton.widthAnchor constraintEqualToConstant:TKAddonActionWidth].active=YES;
        [_updateButton addTarget:self action:@selector(tappedUpdate) forControlEvents:UIControlEventTouchUpInside];
        UIStackView *row=[[UIStackView alloc] initWithArrangedSubviews:@[_checkbox,text,_updateButton]];
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
    _showsManage=NO;
    switch (state) {
        case TKAddonUpdateStateAvailable:
            _updateButton.accessibilityIdentifier=[@"wow.addons.update." stringByAppendingString:identifier];
            [_updateButton setTitle:WKLocalized(@"addons.action.update") forState:UIControlStateNormal];
            _updateButton.enabled=YES;
            _updateButton.hidden=NO;
            break;
        case TKAddonUpdateStateBusy:
            _updateButton.accessibilityIdentifier=[@"wow.addons.update." stringByAppendingString:identifier];
            [_updateButton setTitle:WKLocalized(@"addons.action.updating") forState:UIControlStateNormal];
            _updateButton.enabled=NO;
            _updateButton.hidden=NO;
            break;
        case TKAddonUpdateStateFailed:
            _updateButton.accessibilityIdentifier=[@"wow.addons.update." stringByAppendingString:identifier];
            [_updateButton setTitle:WKLocalized(@"addons.action.retry") forState:UIControlStateNormal];
            _updateButton.enabled=YES;
            _updateButton.hidden=NO;
            break;
        case TKAddonUpdateStateUpToDate:
            _updateButton.accessibilityIdentifier=[@"wow.addons.update." stringByAppendingString:identifier];
            [_updateButton setTitle:WKLocalized(@"addons.action.upToDate") forState:UIControlStateNormal];
            _updateButton.enabled=NO;
            _updateButton.hidden=NO;
            break;
        case TKAddonUpdateStateNotUpdatable:
        case TKAddonUpdateStateUnknown:
        default:
            _showsManage=YES;
            _updateButton.accessibilityIdentifier=[@"wow.addons.manage." stringByAppendingString:identifier];
            [_updateButton setTitle:WKLocalized(@"addons.action.manage") forState:UIControlStateNormal];
            _updateButton.enabled=YES;
            _updateButton.hidden=NO;
            // A visible management action explains ownership and opens Remove for packages this
            // app owns. A greyed empty slot made the installed list look inert.
            break;
    }
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
@property(nonatomic) NSMutableDictionary<NSString *, NSNumber *> *updateStates;
@property(nonatomic) NSUInteger updateGeneration;
@property(nonatomic) BOOL checkingUpdates;
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
@property(nonatomic, copy) NSString *bulkStatus;
@end

@implementation TKWoWAddonManagerViewController
- (instancetype)initWithAddOnsDirectory:(NSString *)directory edition:(NSString *)edition {
    return [self initWithAddOnsDirectory:directory edition:edition browse:NO];
}
- (instancetype)initWithAddOnsDirectory:(NSString *)directory edition:(NSString *)edition browse:(BOOL)browse {
    if (!(self=[super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    _startInBrowse=browse;
    _addOnsDirectory=directory.copy; _edition=edition.copy; _addons=@[]; self.title=WKLocalized(@"addons.title").uppercaseString;
    _store=[[TKAddonStore alloc] initWithAddOnsDirectory:directory product:@"wowf" gameVersion:TKForeverGameVersion]; _results=@[]; _sortField=TKCurseForgeDefaultSortField(); _sortOrder=@"desc";
    _credentials=[TKAddonCredentialStore new];
    _gameVersion=TKForeverGameVersion;
    _selected=[NSMutableSet new]; _installing=[NSMutableSet new];
    _updateCandidates=[NSMutableDictionary new]; _updateStates=[NSMutableDictionary new];
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
    [self updateToolbar];
    if (_startInBrowse) {
        _mode.selectedSegmentIndex=1;
        [self updateToolbar];
        if ([self hasKey]) [self beginBrowse];
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
    _mode=[[UISegmentedControl alloc] initWithItems:@[WKLocalizedFormat(@"addons.mode.installed",(unsigned long)_addons.count),WKLocalized(@"addons.mode.browse")]];
    _mode.selectedSegmentIndex=0; _mode.selectedSegmentTintColor=gold;
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
    _selectAllButton.showsMenuAsPrimaryAction=NO;
    _clearSelectionButton.showsMenuAsPrimaryAction=NO;
    _updateSelectedButton.showsMenuAsPrimaryAction=NO;
    _updateAllButton.showsMenuAsPrimaryAction=NO;
    [_selectAllButton addTarget:self action:@selector(selectAll) forControlEvents:UIControlEventTouchUpInside];
    [_clearSelectionButton addTarget:self action:@selector(clearSelection) forControlEvents:UIControlEventTouchUpInside];
    [_updateSelectedButton addTarget:self action:@selector(tappedUpdateSelected) forControlEvents:UIControlEventTouchUpInside];
    [_updateAllButton addTarget:self action:@selector(tappedUpdateAll) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *toolbar=[[UIStackView alloc] initWithArrangedSubviews:@[_countLabel,_sortButton,_filterButton,_columnsButton,
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
        [_selectAllButton.widthAnchor constraintEqualToConstant:84],
        [_clearSelectionButton.widthAnchor constraintEqualToConstant:64],
        [_updateSelectedButton.widthAnchor constraintEqualToConstant:132],
        [_updateAllButton.widthAnchor constraintEqualToConstant:96],
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
    BOOL browse=_mode.selectedSegmentIndex==1;
    _countLabel.hidden=!browse; _sortButton.hidden=!browse; _filterButton.hidden=!browse; _columnsButton.hidden=!browse;
    _selectionLabel.hidden=browse; _selectAllButton.hidden=browse; _clearSelectionButton.hidden=browse;
    _updateSelectedButton.hidden=browse; _updateAllButton.hidden=browse;
    self.navigationItem.rightBarButtonItems[0].enabled=!self.bulkUpdating;
    _refreshItem.enabled=!_refreshing && !self.bulkUpdating;
    if (!browse) {
        NSUInteger selectable=0;
        for (TKAddonRecord *record in _store.records) if ([self recordIsSelectable:record]) selectable+=1;
        NSUInteger selected=_selected.count;
        NSUInteger updatable=[self allUpdatableRecords].count;
        if (self.bulkStatus.length) _selectionLabel.text=self.bulkStatus;
        else if (self.bulkUpdating) _selectionLabel.text=WKLocalized(@"addons.update.workingMany");
        else _selectionLabel.text=WKLocalizedFormat(@"addons.select.summary",(unsigned long)selected,(unsigned long)updatable);
        _selectAllButton.enabled=!self.bulkUpdating && selectable>selected;
        _clearSelectionButton.enabled=!self.bulkUpdating && selected>0;
        _updateSelectedButton.enabled=!self.bulkUpdating && [self selectedUpdatableRecords].count>0;
        _updateAllButton.enabled=!self.bulkUpdating && updatable>0;
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
    if (_mode.selectedSegmentIndex==1) {
        if (![self hasKey]) { [self setupKey]; return; }
        _refreshing=YES; [self updateToolbar];
        [self reloadAddons];
        [self checkForUpdates];
        _refreshing=NO; [self updateToolbar];
        return;
    }
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
- (void)changeMode:(UISegmentedControl *)sender {
    if (sender.selectedSegmentIndex==1) { if ([self hasKey]) [self beginBrowse]; else _browseStatus=WKLocalized(@"addons.enterKey.long"); }
    [self updateToolbar];
    [self.tableView reloadData];
}
- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar { [searchBar resignFirstResponder]; [self beginBrowse]; }
- (BOOL)hasKey { return [_credentials curseForgeKey:NULL].length>0; }
- (BOOL)canLoadMore { return _results.count>0 && _results.count<_totalCount; }
- (void)beginBrowse { [self fetchPageAtIndex:0 append:NO]; }
- (void)loadMore { if (_loadingMore) return; [self fetchPageAtIndex:_results.count append:YES]; }
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
    NSString *website=nil;
    if ([entry[@"links"] isKindOfClass:NSDictionary.class] && [entry[@"links"][@"websiteUrl"] isKindOfClass:NSString.class]) website=entry[@"links"][@"websiteUrl"];
    if (!website.length && [entry[@"slug"] isKindOfClass:NSString.class]) website=[@"https://www.curseforge.com/wow/addons/" stringByAppendingString:entry[@"slug"]];
    if (website.length) [sheet addAction:[UIAlertAction actionWithTitle:WKLocalized(@"addons.openProject") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){(void)action; NSURL *url=[NSURL URLWithString:website]; if (url) [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];}]];
    [sheet addAction:[UIAlertAction actionWithTitle:WKLocalized(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
    [self presentSheet:sheet from:nil];
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
            [self.tableView reloadData];
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
            if (record) ok=[self.store updateRecord:record archiveURL:[NSURL fileURLWithPath:path] provider:provider error:&storeError];
            else ok=[self.store importZIPAtURL:[NSURL fileURLWithPath:path] provider:provider error:&storeError];
        }
        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
        if (completion) completion();
        dispatch_async(dispatch_get_main_queue(),^{
            if (!ok) { NSError *cause=moveError?:storeError; [self showError:WKLocalized(@"addons.error.installTitle") message:cause.localizedDescription?:WKLocalized(@"addons.error.importMessage")]; return; }
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
    for (NSString *identifier in [_updateStates.allKeys copy]) if (![live containsObject:identifier]) [_updateStates removeObjectForKey:identifier];
    for (NSString *identifier in [_updateCandidates.allKeys copy]) if (![live containsObject:identifier]) [_updateCandidates removeObjectForKey:identifier];
    [self.tableView reloadData];
    [_mode setTitle:WKLocalizedFormat(@"addons.mode.installed",(unsigned long)_store.records.count) forSegmentAtIndex:0];
}

#pragma mark - Update detection, selection and bulk update

- (nullable TKAddonRecord *)recordForIdentifier:(NSString *)identifier {
    for (TKAddonRecord *record in _store.records) if ([record.identifier isEqual:identifier]) return record;
    return nil;
}
- (BOOL)recordIsSelectable:(TKAddonRecord *)record {
    return record.managed && !record.disabled;
}
- (TKAddonUpdateState)stateForRecord:(TKAddonRecord *)record {
    NSNumber *state=_updateStates[record.identifier];
    return state ? (TKAddonUpdateState)state.integerValue : TKAddonUpdateStateUnknown;
}
- (BOOL)recordHasUpdateAvailable:(TKAddonRecord *)record {
    return [self stateForRecord:record]==TKAddonUpdateStateAvailable;
}

// Ask the provider what it currently has for every package that could be updated, then compare
// file identity. Version strings are not compared: two uploads can carry the same display
// version, and a package's own version string is whatever its TOC says.
- (void)checkForUpdates {
    if (_checkingUpdates) return;
    NSString *key=[_credentials curseForgeKey:NULL];
    if (!key.length) return;
    NSMutableArray<TKAddonRecord *> *candidates=[NSMutableArray new];
    for (TKAddonRecord *record in _store.records) {
        if (!record.managed || record.disabled) continue;
        if (!record.providerUpdatable) { _updateStates[record.identifier]=@(TKAddonUpdateStateNotUpdatable); continue; }
        if (record.pinned) { _updateStates[record.identifier]=@(TKAddonUpdateStateNotUpdatable); continue; }
        [candidates addObject:record];
        _updateStates[record.identifier]=@(TKAddonUpdateStateUnknown);
    }
    if (!candidates.count) { [self.tableView reloadData]; return; }
    _checkingUpdates=YES;
    _updateQueue=candidates;
    _updateClient=[[TKCurseForgeClient alloc] initWithAPIKey:key];
    _updateGeneration+=1;
    [self checkNextUpdate];
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
        [self.tableView reloadData];
        return;
    }
    TKAddonRecord *record=_updateQueue.firstObject;
    [_updateQueue removeObjectAtIndex:0];
    NSNumber *projectID=record.provider[TKAddonProviderProjectID];
    NSNumber *currentFile=record.provider[TKAddonProviderFileID];
    NSUInteger generation=_updateGeneration;
    TKCurseForgeClient *client=_updateClient;
    __weak TKWoWAddonManagerViewController *weakSelf=self;
    [client bestFileForModID:projectID gameVersion:TKForeverGameVersion completion:^(TKCurseForgeFileCandidate *candidate,NSError *error){
        dispatch_async(dispatch_get_main_queue(), ^{
            TKWoWAddonManagerViewController *self=weakSelf;
            if (!self) return;
            if (generation != self->_updateGeneration) { self->_checkingUpdates=NO; return; }
            if (error || !candidate) {
                self.updateStates[record.identifier]=@(TKAddonUpdateStateFailed);
            } else {
                NSNumber *newest=candidate.file[@"id"];
                if ([newest isKindOfClass:NSNumber.class] && [newest isEqual:currentFile]) {
                    self.updateStates[record.identifier]=@(TKAddonUpdateStateUpToDate);
                    [self.updateCandidates removeObjectForKey:record.identifier];
                } else {
                    self.updateStates[record.identifier]=@(TKAddonUpdateStateAvailable);
                    if ([candidate.file isKindOfClass:NSDictionary.class]) self.updateCandidates[record.identifier]=candidate.file;
                }
            }
            [self.tableView reloadData];
            [self checkNextUpdate];
        });
    }];
}

- (void)updateRecord:(TKAddonRecord *)record completion:(void (^)(BOOL ok, NSError *error))completion {
    if (!record.providerUpdatable) {
        if (completion) completion(NO, [NSError errorWithDomain:@"WolkaraForever.AddOns" code:1 userInfo:@{NSLocalizedDescriptionKey:WKLocalized(@"addons.update.noProvider")}]);
        return;
    }
    NSString *key=[_credentials curseForgeKey:NULL];
    if (!key.length) { [self setupKey]; if (completion) completion(NO, nil); return; }
    NSNumber *projectID=record.provider[TKAddonProviderProjectID];
    NSNumber *currentFile=record.provider[TKAddonProviderFileID];
    _updateStates[record.identifier]=@(TKAddonUpdateStateBusy);
    [self.tableView reloadData];
    TKCurseForgeClient *client=[[TKCurseForgeClient alloc] initWithAPIKey:key];
    NSDictionary *project=@{ @"id": projectID, @"name": record.name ?: record.identifier };
    [client bestFileForModID:projectID gameVersion:TKForeverGameVersion completion:^(TKCurseForgeFileCandidate *candidate,NSError *error){
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error || !candidate) {
                self.updateStates[record.identifier]=@(TKAddonUpdateStateFailed);
                [self.tableView reloadData];
                if (completion) completion(NO, error);
                return;
            }
            NSNumber *newest=candidate.file[@"id"];
            if ([newest isKindOfClass:NSNumber.class] && [newest isEqual:currentFile]) {
                // The provider already has what is installed. Saying so is the honest answer,
                // and it is the answer that keeps the row from offering the same file again.
                self.updateStates[record.identifier]=@(TKAddonUpdateStateUpToDate);
                [self.tableView reloadData];
                if (completion) completion(YES, nil);
                return;
            }
            [self installCandidate:candidate project:project replacing:record client:client
                              name:record.name ?: record.identifier];
            if (completion) completion(YES, nil);
        });
    }];
}

- (NSArray<TKAddonRecord *> *)selectedUpdatableRecords {
    NSMutableArray<TKAddonRecord *> *records=[NSMutableArray new];
    for (TKAddonRecord *record in _store.records)
        if ([_selected containsObject:record.identifier] && [self recordHasUpdateAvailable:record]) [records addObject:record];
    return records;
}
- (NSArray<TKAddonRecord *> *)allUpdatableRecords {
    NSMutableArray<TKAddonRecord *> *records=[NSMutableArray new];
    for (TKAddonRecord *record in _store.records) if ([self recordHasUpdateAvailable:record]) [records addObject:record];
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
    _bulkQueue=[records mutableCopy];
    _bulkFailures=0;
    [self updateNavigationItems];
    [self runNextBulkUpdate];
}

// One package at a time, so a failure in the middle leaves the packages after it untouched and
// still attempted. A method rather than a recursive block: the block form kept the queue alive
// through its own capture.
- (void)runNextBulkUpdate {
    if (!_bulkQueue.count) {
        // Partial failure is reported by package and does not stop the packages after it.
        self.bulkUpdating=NO;
        self.bulkStatus=nil;
        NSUInteger failed=_bulkFailures;
        _bulkQueue=nil; _bulkFailures=0;
        [self updateNavigationItems];
        [self reloadAddons];
        if (failed) [self showError:WKLocalized(@"addons.error.changeTitle")
                            message:WKLocalizedFormat(@"addons.update.partialFailure",(unsigned long)failed)];
        return;
    }
    TKAddonRecord *record=_bulkQueue.firstObject;
    [_bulkQueue removeObjectAtIndex:0];
    self.bulkStatus=WKLocalizedFormat(@"addons.update.working", record.name ?: record.identifier);
    [self updateNavigationItems];
    __weak TKWoWAddonManagerViewController *weakSelf=self;
    [self updateRecord:record completion:^(BOOL ok, NSError *error){
        (void)error;
        TKWoWAddonManagerViewController *self=weakSelf;
        if (!self) return;
        if (!ok) self->_bulkFailures+=1;
        [self runNextBulkUpdate];
    }];
}

- (void)updateNavigationItems { [self updateToolbar]; }
- (void)tappedUpdateSelected {
    [self confirmBulkUpdate:[self selectedUpdatableRecords]
                      title:WKLocalized(@"addons.update.selectedTitle")
                       verb:WKLocalized(@"addons.select.updateSelected")];
}
- (void)tappedUpdateAll {
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
    if (!url || ![_store importZIPAtURL:url error:&failure]) { }
    if (accessed) [url stopAccessingSecurityScopedResource];
    [self reloadAddons];
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
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { (void)tableView; return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { (void)tableView; if (_mode.selectedSegmentIndex==1) return section==0?0:_results.count+([self canLoadMore]?1:0); return section==0?1:_store.records.count; }
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    (void)tableView;
    if (_mode.selectedSegmentIndex==1 && section==1 && _results.count) {
        TKAddonColumnsHeaderView *header=[[TKAddonColumnsHeaderView alloc] initWithFrame:CGRectMake(0,0,tableView.bounds.size.width,22)];
        [header configureWithColumns:_columns compact:TKAddonRowsAreCompact(self.tableView.bounds.size.width)];
        return header;
    }
    return nil;
}
- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    (void)tableView;
    if (_mode.selectedSegmentIndex==1 && section==1 && _results.count) return 22;
    return UITableViewAutomaticDimension;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { (void)tableView; return _mode.selectedSegmentIndex==0 && section==1?WKLocalized(@"addons.installed"):nil; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    if (_mode.selectedSegmentIndex==1) return section==1?_browseStatus:nil;
    return section==1?WKLocalized(@"addons.installed.footer"):nil;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"addon"];
    if (!cell) cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"addon"];
    cell.selectionStyle=UITableViewCellSelectionStyleDefault;
    if (_mode.selectedSegmentIndex==1 && indexPath.section==0) {
        if (![self hasKey]) { cell.textLabel.text=WKLocalized(@"addons.setUpAccess"); cell.detailTextLabel.text=WKLocalized(@"addons.setUpAccess.detail"); }
        else if (indexPath.row==0) { cell.textLabel.text=WKLocalizedFormat(@"addons.sort.current",BrowseSortLabel(_sortField)); cell.detailTextLabel.text=WKLocalizedFormat(@"addons.sort.tapToChange",[_sortOrder isEqual:@"asc"]?WKLocalized(@"addons.sort.ascending"):WKLocalized(@"addons.sort.descending")); }
        else { cell.textLabel.text=WKLocalizedFormat(@"addons.filters.category",_categoryLabel?:WKLocalized(@"addons.filters.allCategories")); cell.detailTextLabel.text=WKLocalized(@"addons.filters.tapToFilter"); }
    } else if (_mode.selectedSegmentIndex==1) {
        if (indexPath.row==(NSInteger)_results.count) {
            cell.textLabel.text=WKLocalized(@"addons.loadMore");
            cell.detailTextLabel.text=WKLocalizedFormat(@"addons.projectsOfShown",(unsigned long)_results.count,(unsigned long)_totalCount);
        } else {
            TKAddonProjectCell *project=[tableView dequeueReusableCellWithIdentifier:@"project"];
            if (!project) project=[[TKAddonProjectCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"project"];
            NSDictionary *entry=_results[indexPath.row];
            TKCurseForgeFileCandidate *candidate=TKAddonCandidate(entry,_gameVersion);
            NSDictionary *file=candidate.file;
            NSNumber *modID=[entry[@"id"] isKindOfClass:NSNumber.class]?entry[@"id"]:nil;
            project.accessibilityIdentifier=modID?[NSString stringWithFormat:@"wow.addons.project.%@",modID]:@"wow.addons.project";
            NSString *rank=[entry[@"gamePopularityRank"] isKindOfClass:NSNumber.class]?
                [NSString stringWithFormat:@"%@",entry[@"gamePopularityRank"]]:nil;
            BOOL distribution = ![entry[@"allowModDistribution"] isKindOfClass:NSNumber.class] || [entry[@"allowModDistribution"] boolValue];
            TKAddonInstallState state=TKAddonInstallStateIdle;
            if (!distribution) state=TKAddonInstallStateUnavailable;
            else if (modID && [_installing containsObject:modID]) state=TKAddonInstallStateBusy;
            else if ([self installedRecordForProjectID:modID]) state=TKAddonInstallStateInstalled;
            __weak TKWoWAddonManagerViewController *weakSelf=self;
            __weak TKAddonProjectCell *weakProject=project;
            project.onInstall=^{
                TKAddonProjectCell *cell=weakProject;
                TKWoWAddonManagerViewController *self=weakSelf;
                if (!self || !cell) return;
                if (!distribution) { [self presentProject:entry]; return; }
                [self installMod:entry];
            };
            [project configureWithProject:entry file:file rank:rank columns:_columns gameVersion:_gameVersion
                                   compact:TKAddonRowsAreCompact(self.tableView.bounds.size.width)
                              installState:state];
            return project;
        }
    } else if (indexPath.section==0) {
        cell.textLabel.text=_addons.count?WKLocalizedCountFormat(@"addons.count",(NSInteger)_addons.count,(unsigned long)_addons.count):WKLocalized(@"addons.count.none");
        cell.detailTextLabel.text=nil; cell.selectionStyle=UITableViewCellSelectionStyleNone;
    }
    else {
        // An installed package is its own row: a checkbox, the package as a person reads it,
        // and an Update action only when there really is a newer file this app could install.
        TKAddonInstalledCell *installed=[tableView dequeueReusableCellWithIdentifier:@"installed"];
        if (!installed) installed=[[TKAddonInstalledCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"installed"];
        TKAddonRecord *addon=_store.records[indexPath.row];
        __weak TKWoWAddonManagerViewController *weakSelf=self;
        NSString *identifier=addon.identifier;
        installed.onToggleSelection=^(BOOL selected){
            [weakSelf setSelectedIdentifier:identifier selected:selected];
        };
        TKAddonRecord *target=addon;
        installed.onUpdate=^{
            TKWoWAddonManagerViewController *self=weakSelf; if(!self) return;
            [self updateRecord:target completion:^(BOOL ok, NSError *error){
                (void)error;
                if (ok) [self checkForUpdates];
            }];
        };
        installed.onManage=^{
            TKWoWAddonManagerViewController *self=weakSelf; if(!self) return;
            [self presentSheet:[self manageSheetForRecord:target] from:indexPath];
        };
        [installed configureWithRecord:addon
                              selected:[_selected containsObject:identifier]
                            selectable:[self recordIsSelectable:addon]
                                 state:[self recordIsSelectable:addon] ? [self stateForRecord:addon] : TKAddonUpdateStateNotUpdatable
                                detail:[self detailForRecord:addon]];
        return installed;
    }
    cell.backgroundColor=[UIColor colorWithRed:0.07 green:0.09 blue:0.13 alpha:1]; cell.textLabel.textColor=[UIColor colorWithRed:0.9 green:0.72 blue:0.35 alpha:1]; cell.detailTextLabel.textColor=[UIColor colorWithWhite:0.75 alpha:1]; cell.textLabel.numberOfLines=0; cell.detailTextLabel.numberOfLines=0;
    return cell;
}
// The line under an installed package's name: version, where it came from, whether it is
// managed, whether it is pinned, and - when the TOC does not declare Forever's interface - that
// it is unverified. That last word is an advisory, not a refusal.
- (NSString *)detailForRecord:(TKAddonRecord *)addon {
    NSString *state=addon.disabled?WKLocalized(@"addons.state.disabled"):(addon.managed?WKLocalized(@"addons.state.managed"):WKLocalized(@"addons.state.unverified"));
    NSMutableArray<NSString *> *parts=[NSMutableArray arrayWithObjects:addon.version ?: @"", TKAddonSourceName(addon.source), state, nil];
    if (addon.pinned) [parts addObject:WKLocalized(@"addons.state.pinnedShort")];
    if ([addon.compatibility isEqual:TKAddonCompatibilityUnverified] && !addon.disabled)
        [parts addObject:WKLocalized(@"addons.state.notVerifiedForForever")];
    return [parts componentsJoinedByString:@" · "];
}
- (nullable TKAddonRecord *)installedRecordForProjectID:(NSNumber *)projectID {
    if (!projectID) return nil;
    for (TKAddonRecord *record in _store.records) {
        if (!record.managed || !record.providerUpdatable) continue;
        if ([record.provider[TKAddonProviderProjectID] isEqual:projectID]) return record;
    }
    return nil;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (_mode.selectedSegmentIndex==1) {
        if (indexPath.section==0) return;
        if (indexPath.row==(NSInteger)_results.count) { [self loadMore]; return; }
        [self presentProject:_results[indexPath.row]]; return;
    }
    if (indexPath.section==0) return;
    TKAddonRecord *record=_store.records[indexPath.row];
    [self presentSheet:[self manageSheetForRecord:record] from:indexPath];
}
// The actions a managed package offers, built in one place so the page and the device self-test
// exercise the same sheet. The destructive action is what removes a package, and it is here
// rather than only in the row's tap handler because "can I delete anything?" is a question a
// test has to be able to answer without a second pair of hands on the iPad.
- (UIAlertController *)manageSheetForRecord:(TKAddonRecord *)record {
    UIAlertController *sheet=[UIAlertController alertControllerWithTitle:record.name
        message:record.disabled?WKLocalized(@"addons.manage.disabledNote"):WKLocalized(@"addons.manage.note")
        preferredStyle:UIAlertControllerStyleActionSheet];
    if (!record.managed) {
        sheet.message=WKLocalized(@"addons.manage.unmanaged");
        [sheet addAction:[UIAlertAction actionWithTitle:WKLocalized(@"addons.remove") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a){(void)a;[self mutate:^BOOL(NSError **e){return [self.store removeRecord:record error:e];}];}]];
        [sheet addAction:[UIAlertAction actionWithTitle:WKLocalized(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
        return sheet;
    }
    [sheet addAction:[UIAlertAction actionWithTitle:record.disabled?WKLocalized(@"addons.restore"):WKLocalized(@"addons.disable") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){(void)a;[self mutate:^BOOL(NSError **e){return [self.store setDisabled:!record.disabled record:record error:e];}];}]];
    // Pinning is how a user says "leave this one alone". It is honoured by every update path,
    // not only by the row that offers it.
    [sheet addAction:[UIAlertAction actionWithTitle:record.pinned?WKLocalized(@"addons.unpin"):WKLocalized(@"addons.pin") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){(void)a;[self mutate:^BOOL(NSError **e){return [self.store setPinned:!record.pinned record:record error:e];}];}]];
    [sheet addAction:[UIAlertAction actionWithTitle:WKLocalized(@"addons.remove") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a){(void)a;[self mutate:^BOOL(NSError **e){return [self.store removeRecord:record error:e];}];}]];
    [sheet addAction:[UIAlertAction actionWithTitle:WKLocalized(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
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
- (void)setupKey { UIAlertController *a=[UIAlertController alertControllerWithTitle:WKLocalized(@"addons.key.title") message:WKLocalized(@"addons.key.message") preferredStyle:UIAlertControllerStyleAlert];[a addTextFieldWithConfigurationHandler:^(UITextField *f){f.secureTextEntry=YES;f.autocorrectionType=UITextAutocorrectionTypeNo;f.autocapitalizationType=UITextAutocapitalizationTypeNone;f.placeholder=WKLocalized(@"addons.key.placeholder");}];[a addAction:[UIAlertAction actionWithTitle:WKLocalized(@"addons.key.save") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){(void)x;NSError *e=nil;if(![self.credentials storeCurseForgeKey:a.textFields.firstObject.text error:&e]){UIAlertController *failure=[UIAlertController alertControllerWithTitle:WKLocalized(@"addons.key.errorTitle") message:e.localizedDescription preferredStyle:UIAlertControllerStyleAlert];[failure addAction:[UIAlertAction actionWithTitle:WKLocalized(@"common.ok") style:UIAlertActionStyleDefault handler:nil]];[self presentAlert:failure];}else { [self.tableView reloadData]; if (self.mode.selectedSegmentIndex==1) [self beginBrowse]; else [self checkForUpdates]; }}]];[a addAction:[UIAlertAction actionWithTitle:WKLocalized(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];[self presentAlert:a]; }
@end
