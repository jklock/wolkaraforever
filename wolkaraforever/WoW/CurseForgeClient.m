#import "CurseForgeClient.h"
// The app target has WolkaraForeverLog; a standalone host test compiles this
// file on its own. Log when it is there, stay silent when it is not.
#if __has_include("../App/WolkaraForeverLog.h")
#import "../App/WolkaraForeverLog.h"
#define TKAddonLog(...) WKLog("addons", __VA_ARGS__)
#else
#define TKAddonLog(...) do {} while (0)
#endif

static NSString *const BaseURL=@"https://api.curseforge.com/v1";
static NSError *CFError(NSString *message) { return [NSError errorWithDomain:@"WolkaraForever.CurseForge" code:1 userInfo:@{NSLocalizedDescriptionKey:message}]; }

// What CurseForge said, in CurseForge's words. Every 403 used to be reported as "this key
// was rejected", which is true only for the API's own credential check: the edge answers
// with a short plain-text reason ("Forbidden: API Key missing or invalid"), and the
// download endpoint refuses per file and per project with the same status. A user who read
// the old sentence had no way to tell "my key is wrong" from "this author does not allow
// downloads through the API", and the two need different things from them.
static NSString *CFSentText(NSData *data) {
    if (!data.length || data.length > 8192) return @"";
    id value = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    NSString *said = nil;
    if ([value isKindOfClass:NSDictionary.class]) {
        for (NSString *key in @[@"error", @"message", @"errorMessage"]) {
            if ([value[key] isKindOfClass:NSString.class] && [value[key] length]) { said = value[key]; break; }
        }
    }
    if (!said.length) said = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    said = [said stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    said = [said stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\""]];
    if (said.length > 200) said = [[said substringToIndex:200] stringByAppendingString:@"…"];
    return said ?: @"";
}
static NSError *CFHTTPError(NSInteger status, NSData *data) {
    NSString *said = CFSentText(data);
    BOOL namesTheKey = [said rangeOfString:@"api key" options:NSCaseInsensitiveSearch].location != NSNotFound;
    if (status == 403 && namesTheKey && ![said.lowercaseString containsString:@"download"]) {
        return CFError(@"CurseForge rejected this Core API key. Create an approved Core API key in the developer console.");
    }
    NSString *reason;
    switch (status) {
        case 400: reason = @"CurseForge refused the request as malformed."; break;
        case 401: reason = @"CurseForge did not accept this Core API key."; break;
        case 403: reason = @"CurseForge refused this request. If the key works for searching, this project or file does not allow downloads through the API: install it from its project page instead."; break;
        case 404: reason = @"CurseForge has no such project or file."; break;
        case 429: reason = @"CurseForge is rate limiting this key. Wait a minute, then try again."; break;
        default:
            reason = status >= 500 ? @"CurseForge is having trouble right now. Try again shortly."
                                   : [NSString stringWithFormat:@"CurseForge API returned HTTP %ld.", (long)status];
            break;
    }
    if (said.length && ![said.lowercaseString hasSuffix:@"forbidden"]) reason = [reason stringByAppendingFormat:@" (%@)", said];
    return CFError(reason);
}

@interface TKCurseForgeSortField ()
@property (nonatomic, readwrite) NSInteger wireValue;
@property (nonatomic, readwrite, copy) NSString *titleKey;
@property (nonatomic, readwrite) BOOL defaultsToAscending;
@end

@implementation TKCurseForgeSortField
@end

@interface TKCurseForgeFileCandidate ()
@property (nonatomic, readwrite, copy) NSDictionary *file;
@property (nonatomic, readwrite) TKCurseForgeCompatibility compatibility;
@property (nonatomic, readwrite, copy) NSArray<NSString *> *gameVersions;
@end

static TKCurseForgeSortField *CFSortField(NSInteger wire, NSString *key, BOOL ascending) {
    TKCurseForgeSortField *field = [TKCurseForgeSortField new];
    field.wireValue = wire;
    field.titleKey = key;
    field.defaultsToAscending = ascending;
    return field;
}

NSArray<TKCurseForgeSortField *> *TKCurseForgeSortFields(void) {
    static NSArray<TKCurseForgeSortField *> *fields;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // CurseForge's own field ids and its own words: Featured, Popularity, Last Updated,
        // Name, Author, Total Downloads, Release Date. A field this build does not list is not
        // offered, so a visible control can never show a bare number.
        fields = @[
            CFSortField(1,  @"addons.sort.featured",       NO),
            CFSortField(2,  @"addons.sort.popularity",     NO),
            CFSortField(3,  @"addons.sort.lastUpdated",    NO),
            CFSortField(4,  @"addons.column.name",         YES),
            CFSortField(5,  @"addons.column.author",       YES),
            CFSortField(6,  @"addons.sort.totalDownloads", NO),
            CFSortField(11, @"addons.sort.releaseDate",    NO),
        ];
    });
    return fields;
}

TKCurseForgeSortField *TKCurseForgeSortFieldForWireValue(NSInteger value) {
    for (TKCurseForgeSortField *field in TKCurseForgeSortFields())
        if (field.wireValue == value) return field;
    return nil;
}

NSInteger TKCurseForgeDefaultSortField(void) { return 1; }

@implementation TKCurseForgeFileCandidate
@end

// The one place a project's file list becomes a decision. Everything that can be decided from
// the list alone lives here, so the browser list and the install path cannot disagree about
// which file a project would install.
TKCurseForgeFileCandidate *TKCurseForgeChooseFile(NSArray *files, NSString *gameVersion) {    if (![files isKindOfClass:NSArray.class]) return nil;
    NSMutableArray<NSDictionary *> *available = [NSMutableArray array];
    for (id item in files) {
        if (![item isKindOfClass:NSDictionary.class]) continue;
        if (![item[@"fileDate"] isKindOfClass:NSString.class]) continue;
        if (![item[@"id"] isKindOfClass:NSNumber.class]) continue;
        // `isAvailable` is the author's and CurseForge's own "may be downloaded" flag. A file
        // that is not available is not a candidate at any compatibility level.
        if ([item[@"isAvailable"] isKindOfClass:NSNumber.class] && ![item[@"isAvailable"] boolValue]) continue;
        [available addObject:item];
    }
    NSArray<NSDictionary *> *sorted = [available sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [b[@"fileDate"] compare:a[@"fileDate"]];
    }];
    NSMutableArray<NSDictionary *> *matching = [NSMutableArray array];
    if (gameVersion.length) {
        for (NSDictionary *file in sorted) {
            NSArray *versions = [file[@"gameVersions"] isKindOfClass:NSArray.class] ? file[@"gameVersions"] : @[];
            if ([versions containsObject:gameVersion]) [matching addObject:file];
        }
    }
    NSDictionary *chosen = matching.firstObject ?: sorted.firstObject;
    if (!chosen) return nil;
    TKCurseForgeFileCandidate *candidate = [TKCurseForgeFileCandidate new];
    candidate.file = chosen;
    candidate.compatibility = matching.count ? TKCurseForgeCompatibilityVerified : TKCurseForgeCompatibilityUnverified;
    candidate.gameVersions = [chosen[@"gameVersions"] isKindOfClass:NSArray.class] ? chosen[@"gameVersions"] : @[];
    return candidate;
}

@implementation TKCurseForgeClient { NSString *_key; NSURLSession *_session; }
- (instancetype)initWithAPIKey:(NSString *)key { if((self=[super init])){_key=key.copy;_session=[NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.ephemeralSessionConfiguration];}return self; }
- (void)get:(NSString *)path completion:(TKCurseForgeCompletion)completion {
    NSURL *url=[NSURL URLWithString:[BaseURL stringByAppendingString:path]]; if(!url){completion(nil,CFError(@"Invalid CurseForge API URL."));return;}
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:url];[request setValue:@"application/json" forHTTPHeaderField:@"Accept"];[request setValue:_key forHTTPHeaderField:@"x-api-key"];
    NSURLSessionDataTask *task=[_session dataTaskWithRequest:request completionHandler:^(NSData *data,NSURLResponse *response,NSError *failure){NSHTTPURLResponse *http=(id)response;if(failure){completion(nil,failure);return;}if(http.statusCode<200||http.statusCode>=300){NSError *refusal=CFHTTPError(http.statusCode,data);TKAddonLog(@"GET %@ -> HTTP %ld: %@",path,(long)http.statusCode,refusal.localizedDescription);completion(nil,refusal);return;}id value=[NSJSONSerialization JSONObjectWithData:data options:0 error:&failure];if(![value isKindOfClass:NSDictionary.class]||failure){completion(nil,CFError(@"CurseForge returned invalid JSON."));return;}id payload=value[@"data"];if(!payload || payload == NSNull.null){completion(nil,CFError(@"CurseForge returned no data."));return;}completion(payload,nil);}];
    [task resume];
}
- (void)categoriesForGameID:(NSInteger)gameID completion:(TKCurseForgeCompletion)completion { [self get:[NSString stringWithFormat:@"/categories?gameId=%ld",(long)gameID] completion:completion]; }
- (void)browseModsWithQuery:(NSString *)query sortField:(NSInteger)sortField sortOrder:(NSString *)sortOrder categoryID:(NSNumber *)categoryID index:(NSUInteger)index completion:(TKCurseForgeCompletion)completion {
    [self browseModsWithQuery:query sortField:sortField sortOrder:sortOrder categoryID:categoryID
                  gameVersion:nil classID:nil index:index completion:completion];
}
- (void)browseModsWithQuery:(NSString *)query sortField:(NSInteger)sortField sortOrder:(NSString *)sortOrder categoryID:(NSNumber *)categoryID gameVersion:(NSString *)gameVersion classID:(NSNumber *)classID index:(NSUInteger)index completion:(TKCurseForgeCompletion)completion {
    NSURLComponents *c=[NSURLComponents componentsWithString:@"https://placeholder"]; NSMutableArray *items=[@[[NSURLQueryItem queryItemWithName:@"gameId" value:@"1"],[NSURLQueryItem queryItemWithName:@"pageSize" value:@"50"],[NSURLQueryItem queryItemWithName:@"index" value:[NSString stringWithFormat:@"%lu",(unsigned long)index]],[NSURLQueryItem queryItemWithName:@"sortField" value:[NSString stringWithFormat:@"%ld",(long)sortField]],[NSURLQueryItem queryItemWithName:@"sortOrder" value:sortOrder?:@"desc"]] mutableCopy];
    if(query.length)[items addObject:[NSURLQueryItem queryItemWithName:@"searchFilter" value:query]];
    if(categoryID)[items addObject:[NSURLQueryItem queryItemWithName:@"categoryId" value:categoryID.stringValue]];
    if(gameVersion.length)[items addObject:[NSURLQueryItem queryItemWithName:@"gameVersion" value:gameVersion]];
    if(classID)[items addObject:[NSURLQueryItem queryItemWithName:@"classId" value:classID.stringValue]];
    c.queryItems=items;
    NSURL *url=[NSURL URLWithString:[BaseURL stringByAppendingFormat:@"/mods/search?%@",c.percentEncodedQuery]]; NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:url];[request setValue:@"application/json" forHTTPHeaderField:@"Accept"];[request setValue:_key forHTTPHeaderField:@"x-api-key"];
    [[_session dataTaskWithRequest:request completionHandler:^(NSData *data,NSURLResponse *response,NSError *failure){NSHTTPURLResponse *http=(id)response;if(failure){TKAddonLog(@"mods/search failed: %@",failure.localizedDescription);completion(nil,failure);return;}if(http.statusCode<200||http.statusCode>=300){NSError *refusal=CFHTTPError(http.statusCode,data);TKAddonLog(@"mods/search -> HTTP %ld: %@",(long)http.statusCode,refusal.localizedDescription);completion(nil,refusal);return;}id value=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL]:nil;if(![value isKindOfClass:NSDictionary.class]){completion(nil,CFError(@"CurseForge returned invalid JSON."));return;}if(![value[@"data"] isKindOfClass:NSArray.class]){completion(nil,CFError(@"CurseForge returned no mod list."));return;}completion(value,nil);} ] resume];
}
- (void)fetchFilesForModID:(NSNumber *)modID completion:(void (^)(NSArray *_Nullable files, NSError *_Nullable error))completion {
    [self get:[NSString stringWithFormat:@"/mods/%@/files?pageSize=50", modID] completion:^(id value, NSError *error) {
        if (error) { completion(nil, error); return; }
        if (![value isKindOfClass:NSArray.class]) { completion(nil, CFError(@"CurseForge returned an invalid file list.")); return; }
        completion(value, nil);
    }];
}
- (void)bestFileForModID:(NSNumber *)modID gameVersion:(NSString *)gameVersion
              completion:(void (^)(TKCurseForgeFileCandidate *_Nullable candidate, NSError *_Nullable error))completion {
    [self fetchFilesForModID:modID completion:^(NSArray *files, NSError *error) {
        if (error) { completion(nil, error); return; }
        TKCurseForgeFileCandidate *candidate = TKCurseForgeChooseFile(files, gameVersion);
        if (!candidate) {
            // Nothing downloadable at all. That is a broken or empty answer rather than a
            // compatibility state, and saying so is the difference between "this project has
            // no file you can have" and "this project is not verified for your version".
            completion(nil, CFError([NSString stringWithFormat:@"This project has no downloadable file (looking for %@).", gameVersion ?: @"any version"]));
            return;
        }
        completion(candidate, nil);
    }];
}
- (void)latestFileForModID:(NSNumber *)modID gameVersion:(NSString *)gameVersion completion:(TKCurseForgeCompletion)completion {
    [self bestFileForModID:modID gameVersion:gameVersion completion:^(TKCurseForgeFileCandidate *candidate, NSError *error) {
        if (error) { completion(nil, error); return; }
        if (candidate.compatibility != TKCurseForgeCompatibilityVerified) {
            completion(nil, CFError([NSString stringWithFormat:@"This project has no file tagged %@.", gameVersion]));
            return;
        }
        completion(candidate.file, nil);
    }];
}
- (void)downloadURLForModID:(NSNumber *)modID fileID:(NSNumber *)fileID completion:(TKCurseForgeCompletion)completion { [self get:[NSString stringWithFormat:@"/mods/%@/files/%@/download-url",modID,fileID] completion:^(id value,NSError *error){if(error){completion(nil,error);return;}completion([value isKindOfClass:NSString.class]?value:nil,[value isKindOfClass:NSString.class]?nil:CFError(@"CurseForge returned an invalid download URL."));}]; }
- (NSURLRequest *)assetRequestForURL:(NSString *)string error:(NSError **)error {
    NSURL *url=[NSURL URLWithString:string]; NSString *host=url.host.lowercaseString;
    if(![url.scheme.lowercaseString isEqual:@"https"] || !([host isEqual:@"forgecdn.net"] || [host hasSuffix:@".forgecdn.net"])) { if(error)*error=CFError(@"CurseForge returned an untrusted asset host."); return nil; }
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:url];
    // CurseForge now attributes CDN downloads through the same API credential, so the key goes
    // with the request. Reviewed 2026-10-17 and left as it is: the allowlist above is
    // CurseForge's own domain, and the only caller in the app passes a URL this client has just
    // been given by the API. Anything that changes who calls this method inherits the question,
    // which is why it is written down here rather than left to the header.
    [request setValue:_key forHTTPHeaderField:@"x-api-key"];
    return request;
}
@end
