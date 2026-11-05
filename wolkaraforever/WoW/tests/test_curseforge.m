#import "CurseForgeClient.h"
#include <stdio.h>

// A fake transport feeds the real client's parser. No key or network is used.
@interface TestTask : NSObject
@property(copy) void (^action)(void);
- (void)resume;
@end
@implementation TestTask
- (void)resume { self.action(); }
@end
@interface TestSession : NSObject
@property NSInteger status;
@property(copy) NSString *body;
@property(strong) NSError *failure;
@property(strong) NSURLRequest *request;
@end
@implementation TestSession
- (id)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completion {
    self.request = request;
    TestTask *task = [TestTask new];
    task.action = ^{ completion([self.body dataUsingEncoding:NSUTF8StringEncoding], [[NSHTTPURLResponse alloc] initWithURL:request.URL statusCode:self.status HTTPVersion:@"HTTP/1.1" headerFields:@{}], self.failure); };
    return task;
}
@end
#define CHECK(x, label) do { checks++; if (!(x)) { fprintf(stderr,"FAIL: %s\n",label); return 1; } } while (0)
int main(void) {
    @autoreleasepool {
        NSUInteger checks = 0;
        TKCurseForgeClient *client = [[TKCurseForgeClient alloc] initWithAPIKey:@"fixture-key"];
        TestSession *session = [TestSession new];
        [client setValue:session forKey:@"session"];
        __block id result;
        __block NSError *error;
        __block NSUInteger calls;
        TKCurseForgeCompletion completion = ^(id value, NSError *problem) { result=value; error=problem; calls++; };
        for (NSString *body in @[@"[]", @"null", @"broken", @"{}", @"{\"data\":null}"]) {
            session.status = 200; session.body = body; calls=0;
            [client categoriesForGameID:1 completion:completion];
            CHECK(error && !result && calls==1, "malformed response fails once without exception");
        }
        for (NSNumber *status in @[@401, @403, @429, @500]) {
            session.status=status.integerValue; session.body=@"{}";
            [client categoriesForGameID:1 completion:completion];
            CHECK(error && !result, "HTTP failure reported");
        }
        // A 403 is not one thing. The edge refuses a bad credential with a plain-text reason, and
        // the download endpoint refuses a *file* with the same status. Reporting both as "this key
        // was rejected" is what made a working key look broken on the device (2026-10-22) while the
        // real answer was that the project does not allow downloads through the API.
        session.status=403; session.body=@"Forbidden: API Key missing or invalid";
        [client categoriesForGameID:1 completion:completion];
        CHECK([error.localizedDescription containsString:@"rejected this Core API key"], "a refused credential names the key");
        session.status=403; session.body=@"{\"error\":\"This file is not available for third-party download\"}";
        [client downloadURLForModID:@1 fileID:@2 completion:completion];
        CHECK([error.localizedDescription containsString:@"does not allow downloads"], "a refused file does not blame the key");
        session.status=429; session.body=@"";
        [client categoriesForGameID:1 completion:completion];
        CHECK([error.localizedDescription containsString:@"rate limiting"], "a rate limit says so");
        session.status=200; session.body=@"{\"data\":[]}";
        [client categoriesForGameID:1 completion:completion];
        CHECK([result isKindOfClass:NSArray.class] && !error, "valid categories");
        CHECK([[session.request valueForHTTPHeaderField:@"x-api-key"] isEqual:@"fixture-key"], "API credential header");
        [client browseModsWithQuery:@"a&b café" sortField:2 sortOrder:@"desc" categoryID:@42 index:50 completion:completion];
        CHECK([result isKindOfClass:NSDictionary.class] && !error, "browse preserves pagination envelope");
        NSURLComponents *parts=[NSURLComponents componentsWithURL:session.request.URL resolvingAgainstBaseURL:NO];
        NSMutableDictionary *query=[NSMutableDictionary new];
        for (NSURLQueryItem *item in parts.queryItems) query[item.name]=item.value;
        CHECK([query[@"searchFilter"] isEqual:@"a&b café"] && [query[@"index"] isEqual:@"50"], "query encoding and pagination");
        // A browse answer with no mod list is not a browse answer. It used to be accepted,
        // because only the envelope was checked, and the caller then saw an empty list rather
        // than an error - which reads exactly like "this search found nothing".
        for (NSString *body in @[@"{}", @"{\"data\":null}", @"{\"data\":{}}"]) {
            session.status=200; session.body=body; calls=0;
            [client browseModsWithQuery:@"" sortField:2 sortOrder:@"desc" categoryID:nil index:0 completion:completion];
            CHECK(error && !result && calls==1, "a browse answer with no mod list fails once without exception");
        }
        session.body=@"{\"data\":[null,42,{}, {\"gameVersions\":[\"1.60.1\"],\"isAvailable\":true,\"fileDate\":\"2026-01-01\",\"id\":1}, {\"gameVersions\":[\"1.60.1\"],\"isAvailable\":true,\"fileDate\":\"2026-02-01\",\"id\":2}]}";
        [client latestFileForModID:@1 gameVersion:@"1.60.1" completion:completion];
        CHECK([result[@"id"] isEqual:@2] && !error, "invalid entries ignored; newest compatible file chosen");
        // --- the sort table is the only source of a visible sort name
        NSArray<TKCurseForgeSortField *> *sorts=TKCurseForgeSortFields();
        CHECK(sorts.count==7, "seven sort fields, as the site offers");
        CHECK(sorts.firstObject.wireValue==1 && [sorts.firstObject.titleKey isEqual:@"addons.sort.featured"], "featured first, by wire id");
        CHECK(TKCurseForgeSortFieldForWireValue(11).wireValue==11, "release date is reachable by its wire id");
        CHECK(TKCurseForgeSortFieldForWireValue(99)==nil, "an unlisted wire id has no name and is not offered");
        for (TKCurseForgeSortField *field in sorts) {
            CHECK(field.titleKey.length>0 && ![field.titleKey containsString:@"%@"], "every visible sort name is a localization key, not a format");
            // The direction each field starts in is data, not a hard-coded pair of ids in the menu.
            if (field.wireValue==4 || field.wireValue==5) CHECK(field.defaultsToAscending, "name and author read A-Z");
            else CHECK(!field.defaultsToAscending, "everything else reads largest or newest first");
        }
        CHECK(TKCurseForgeDefaultSortField()==1, "featured is what the list shows before a choice");
        // --- the file a row shows is the file the button installs
        NSString *twoFiles=@"{\"data\":[{\"id\":1,\"gameVersions\":[\"1.15.9\"],\"isAvailable\":true,\"fileDate\":\"2026-05-01\"}, {\"id\":2,\"gameVersions\":[\"1.60.1\"],\"isAvailable\":true,\"fileDate\":\"2026-03-01\"}]}";
        session.status=200; session.body=twoFiles;
        __block TKCurseForgeFileCandidate *candidate=nil;
        [client bestFileForModID:@1 gameVersion:@"1.60.1" completion:^(TKCurseForgeFileCandidate *value,NSError *problem){
            candidate=value; error=problem;
        }];
        CHECK(candidate && [candidate.file[@"id"] isEqual:@2] && candidate.compatibility==TKCurseForgeCompatibilityVerified && !error,
              "a tagged file wins even when a newer untagged one exists");
        // No Forever-tagged file at all is *not* a refusal: the newest available file is
        // offered and the compatibility state says it is unverified. That is the difference
        // between advice and a gate, and the plan removes the gate.
        session.body=@"{\"data\":[{\"id\":3,\"gameVersions\":[\"1.15.9\"],\"isAvailable\":true,\"fileDate\":\"2026-06-01\"}]}";
        [client bestFileForModID:@1 gameVersion:@"1.60.1" completion:^(TKCurseForgeFileCandidate *value,NSError *problem){
            candidate=value; error=problem;
        }];
        CHECK(candidate && [candidate.file[@"id"] isEqual:@3] && candidate.compatibility==TKCurseForgeCompatibilityUnverified && !error,
              "an untagged file is offered as unverified instead of denied");
        CHECK([candidate.gameVersions isEqual:@[@"1.15.9"]], "and it carries the versions it does declare, for the advisory line");
        // Nothing downloadable at all is still a refusal, because it is a broken answer rather
        // than a compatibility state.
        session.body=@"{\"data\":[{\"id\":4,\"gameVersions\":[\"1.60.1\"],\"isAvailable\":false,\"fileDate\":\"2026-07-01\"}]}";
        [client bestFileForModID:@1 gameVersion:@"1.60.1" completion:^(TKCurseForgeFileCandidate *value,NSError *problem){
            candidate=value; error=problem;
        }];
        CHECK(!candidate && error, "a project with no available file is refused");
        session.body=@"{\"data\":[]}";
        [client bestFileForModID:@1 gameVersion:@"1.60.1" completion:^(TKCurseForgeFileCandidate *value,NSError *problem){
            candidate=value; error=problem;
        }];
        CHECK(!candidate && error, "an empty file list is refused");
        // The compatible-only accessor keeps its old meaning for a caller that wants it.
        session.body=@"{\"data\":[{\"id\":5,\"gameVersions\":[\"1.15.9\"],\"isAvailable\":true,\"fileDate\":\"2026-08-01\"}]}";
        [client latestFileForModID:@1 gameVersion:@"1.60.1" completion:completion];
        CHECK(!result && error, "latestFileForModID still means 'none' when nothing matches");
        for (NSString *url in @[@"http://edge.forgecdn.net/a", @"https://forgecdn.net.evil.test/a", @"https://example.org/a"]) {
            NSError *failure=nil;
            CHECK(![client assetRequestForURL:url error:&failure] && failure, "untrusted asset URL refused");
        }
        NSError *failure=nil;
        CHECK([[client assetRequestForURL:@"https://edge.forgecdn.net/a" error:&failure] valueForHTTPHeaderField:@"x-api-key"] != nil, "approved CDN request");
        // The last step of the live install path, which nothing reached before: the URL the API
        // hands back is what the asset request is built from.
        session.status=200; session.body=@"{\"data\":\"https://edge.forgecdn.net/files/1/2/thing.zip\"}";
        [client downloadURLForModID:@1 fileID:@2 completion:completion];
        CHECK([result isEqual:@"https://edge.forgecdn.net/files/1/2/thing.zip"] && !error, "a download URL comes back as a string");
        session.status=200; session.body=@"{\"data\":{\"not\":\"a string\"}}";
        [client downloadURLForModID:@1 fileID:@2 completion:completion];
        CHECK(error && !result, "and an answer that is not a URL is refused");
        session.failure=[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNotConnectedToInternet userInfo:nil];
        [client categoriesForGameID:1 completion:completion];
        CHECK(error==session.failure && !result, "transport error preserved");
        printf("CURSEFORGE PASS: %lu checks, no network or credentials\n", (unsigned long)checks);
    }
    return 0;
}
