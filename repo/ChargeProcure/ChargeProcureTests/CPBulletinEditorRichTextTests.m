#import <XCTest/XCTest.h>
#import "CPBulletinService.h"
#import "CPAuthService.h"
#import "CPCoreDataStack.h"
#import "CPTestCoreDataStack.h"
#import "CPBulletin+CoreDataProperties.h"
#import <CoreData/CoreData.h>

/// Known password for all accounts in this suite.
static NSString * const kRTTestPass = @"Test1234Pass";

// ---------------------------------------------------------------------------
// CPBulletinEditorRichTextTests
//
// Tests that verify the WYSIWYG rich-text editing pipeline end-to-end:
//   - bodyHTML is persisted separately from bodyMarkdown (body field)
//   - Autosave stores HTML for WYSIWYG drafts
//   - Publish snapshot records bodyHTML in BulletinVersion
//   - Restore version copies bodyHTML back to the bulletin
//   - Markdown-mode bulletins have no bodyHTML
//   - Round-trip: content written as HTML is readable after fetch
// ---------------------------------------------------------------------------

@interface CPBulletinEditorRichTextTests : XCTestCase
@end

@implementation CPBulletinEditorRichTextTests

- (void)setUp {
    [super setUp];
    [[CPTestCoreDataStack sharedStack] resetAll];
    [[CPAuthService sharedService] logout];

    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [[CPCoreDataStack sharedStack] performBackgroundTask:^(NSManagedObjectContext *ctx) {
        for (NSManagedObject *u in [ctx executeFetchRequest:
             [NSFetchRequest fetchRequestWithEntityName:@"User"] error:nil])
            [ctx deleteObject:u];
        for (NSManagedObject *r in [ctx executeFetchRequest:
             [NSFetchRequest fetchRequestWithEntityName:@"Role"] error:nil])
            [ctx deleteObject:r];
        [ctx save:nil];
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"cp_must_change_password_uuids"];
    [[NSUserDefaults standardUserDefaults] synchronize];

    [[CPAuthService sharedService] seedDefaultUsersWithPassword:kRTTestPass];
    [self loginAs:@"admin" password:kRTTestPass];
}

- (void)tearDown {
    [[CPAuthService sharedService] logout];
    [[CPTestCoreDataStack sharedStack] resetAll];
    [super tearDown];
}

- (void)loginAs:(NSString *)username password:(NSString *)password {
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [[CPAuthService sharedService] loginWithUsername:username password:password
                                         completion:^(BOOL success, NSError *err) {
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
}

// ---------------------------------------------------------------------------
// 1. autosaveDraft stores bodyHTML when provided
// ---------------------------------------------------------------------------

- (void)testAutosavePersistsBodyHTML {
    NSError *err = nil;
    NSString *uuid = [[CPBulletinService sharedService]
                      createDraftWithTitle:@"Rich Test" editorMode:@"WYSIWYG" error:&err];
    XCTAssertNotNil(uuid);
    XCTAssertNil(err);

    NSString *html = @"<b>Hello World</b>";
    BOOL saved = [[CPBulletinService sharedService]
                  autosaveDraft:uuid
                          title:@"Rich Test"
                        summary:nil
                   bodyMarkdown:@"Hello World"
                       bodyHTML:html
                          error:&err];
    XCTAssertTrue(saved, @"Autosave should succeed");
    XCTAssertNil(err);

    // Fetch from main context and verify bodyHTML was stored
    NSManagedObjectContext *ctx = [CPCoreDataStack sharedStack].mainContext;
    __block NSString *fetchedHTML = nil;
    [ctx performBlockAndWait:^{
        NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"Bulletin"];
        req.predicate = [NSPredicate predicateWithFormat:@"uuid == %@", uuid];
        req.fetchLimit = 1;
        CPBulletin *b = [[ctx executeFetchRequest:req error:nil] firstObject];
        fetchedHTML = b.bodyHTML;
    }];
    XCTAssertEqualObjects(fetchedHTML, html,
                          @"bodyHTML must be stored as provided during autosave");
}

// ---------------------------------------------------------------------------
// 2. Markdown-mode autosave does NOT store bodyHTML
// ---------------------------------------------------------------------------

- (void)testMarkdownAutosaveDoesNotPersistBodyHTML {
    NSError *err = nil;
    NSString *uuid = [[CPBulletinService sharedService]
                      createDraftWithTitle:@"MD Draft" editorMode:@"Markdown" error:&err];
    XCTAssertNotNil(uuid);

    BOOL saved = [[CPBulletinService sharedService]
                  autosaveDraft:uuid
                          title:@"MD Draft"
                        summary:nil
                   bodyMarkdown:@"## Heading\n\nBody"
                       bodyHTML:nil
                          error:&err];
    XCTAssertTrue(saved);
    XCTAssertNil(err);

    NSManagedObjectContext *ctx = [CPCoreDataStack sharedStack].mainContext;
    __block NSString *fetchedHTML = nil;
    [ctx performBlockAndWait:^{
        NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"Bulletin"];
        req.predicate = [NSPredicate predicateWithFormat:@"uuid == %@", uuid];
        req.fetchLimit = 1;
        CPBulletin *b = [[ctx executeFetchRequest:req error:nil] firstObject];
        fetchedHTML = b.bodyHTML;
    }];
    XCTAssertNil(fetchedHTML,
                 @"bodyHTML must be nil for a Markdown-mode draft (bodyHTML:nil passed)");
}

// ---------------------------------------------------------------------------
// 3. Publish creates BulletinVersion with bodyHTML
// ---------------------------------------------------------------------------

- (void)testPublishSnapshotsBodyHTMLInVersion {
    NSError *err = nil;
    NSString *uuid = [[CPBulletinService sharedService]
                      createDraftWithTitle:@"Rich Publish" editorMode:@"WYSIWYG" error:&err];
    XCTAssertNotNil(uuid);

    NSString *html = @"<h1>Title</h1><p>Content</p>";
    [[CPBulletinService sharedService]
     autosaveDraft:uuid title:@"Rich Publish" summary:@"Summary"
      bodyMarkdown:@"Title\n\nContent" bodyHTML:html error:nil];

    BOOL published = [[CPBulletinService sharedService]
                      publishBulletin:uuid
                             publishAt:nil
                           unpublishAt:nil
                  recommendationWeight:50
                              isPinned:NO
                                 error:&err];
    XCTAssertTrue(published, @"Publish should succeed");
    XCTAssertNil(err);

    // Check that BulletinVersion recorded bodyHTML
    NSManagedObjectContext *ctx = [CPCoreDataStack sharedStack].mainContext;
    __block NSString *versionHTML = nil;
    [ctx performBlockAndWait:^{
        NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"BulletinVersion"];
        req.predicate = [NSPredicate predicateWithFormat:@"bulletinID == %@", uuid];
        req.fetchLimit = 1;
        NSManagedObject *ver = [[ctx executeFetchRequest:req error:nil] firstObject];
        versionHTML = [ver valueForKey:@"bodyHTML"];
    }];
    XCTAssertEqualObjects(versionHTML, html,
                          @"BulletinVersion must store the HTML body at publish time");
}

// ---------------------------------------------------------------------------
// 4. Restore version copies bodyHTML back onto the bulletin
// ---------------------------------------------------------------------------

- (void)testRestoreVersionRestoresBodyHTML {
    NSError *err = nil;
    NSString *uuid = [[CPBulletinService sharedService]
                      createDraftWithTitle:@"Restore Rich" editorMode:@"WYSIWYG" error:&err];
    XCTAssertNotNil(uuid);

    NSString *originalHTML = @"<b>Original</b>";
    [[CPBulletinService sharedService]
     autosaveDraft:uuid title:@"Restore Rich" summary:nil
      bodyMarkdown:@"Original" bodyHTML:originalHTML error:nil];
    [[CPBulletinService sharedService]
     publishBulletin:uuid publishAt:nil unpublishAt:nil
     recommendationWeight:0 isPinned:NO error:nil];

    // Fetch the version UUID
    NSManagedObjectContext *ctx = [CPCoreDataStack sharedStack].mainContext;
    __block NSString *versionUUID = nil;
    [ctx performBlockAndWait:^{
        NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"BulletinVersion"];
        req.predicate = [NSPredicate predicateWithFormat:@"bulletinID == %@", uuid];
        req.fetchLimit = 1;
        NSManagedObject *ver = [[ctx executeFetchRequest:req error:nil] firstObject];
        versionUUID = [ver valueForKey:@"uuid"];
    }];
    XCTAssertNotNil(versionUUID);

    // Overwrite the bulletin with different content
    [[CPBulletinService sharedService]
     autosaveDraft:uuid title:@"Restore Rich" summary:nil
      bodyMarkdown:@"Changed" bodyHTML:@"<i>Changed</i>" error:nil];

    // Restore the original version
    BOOL restored = [[CPBulletinService sharedService]
                     restoreVersion:versionUUID toBulletin:uuid error:&err];
    XCTAssertTrue(restored, @"Restore should succeed");
    XCTAssertNil(err);

    // Verify bodyHTML was restored
    __block NSString *restoredHTML = nil;
    [ctx performBlockAndWait:^{
        NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"Bulletin"];
        req.predicate = [NSPredicate predicateWithFormat:@"uuid == %@", uuid];
        req.fetchLimit = 1;
        [ctx refreshObject:[[ctx executeFetchRequest:req error:nil] firstObject] mergeChanges:YES];
        CPBulletin *b = [[ctx executeFetchRequest:req error:nil] firstObject];
        restoredHTML = b.bodyHTML;
    }];
    XCTAssertEqualObjects(restoredHTML, originalHTML,
                          @"bodyHTML must be restored from the version snapshot");
}

// ---------------------------------------------------------------------------
// 5. bodyHTML field survives a Core Data round-trip (save + re-fetch)
// ---------------------------------------------------------------------------

- (void)testBodyHTMLRoundTrip {
    NSError *err = nil;
    NSString *uuid = [[CPBulletinService sharedService]
                      createDraftWithTitle:@"Round Trip" editorMode:@"WYSIWYG" error:&err];
    XCTAssertNotNil(uuid);

    NSString *html = @"<p>Round <b>trip</b> test.</p>";
    [[CPBulletinService sharedService]
     autosaveDraft:uuid title:@"Round Trip" summary:nil
      bodyMarkdown:@"Round trip test." bodyHTML:html error:nil];

    // Re-fetch from a new background context
    __block NSString *fetched = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [[CPCoreDataStack sharedStack] performBackgroundTask:^(NSManagedObjectContext *ctx) {
        NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"Bulletin"];
        req.predicate = [NSPredicate predicateWithFormat:@"uuid == %@", uuid];
        req.fetchLimit = 1;
        CPBulletin *b = [[ctx executeFetchRequest:req error:nil] firstObject];
        fetched = b.bodyHTML;
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));

    XCTAssertEqualObjects(fetched, html,
                          @"bodyHTML must survive a Core Data save/fetch round-trip");
}

// ---------------------------------------------------------------------------
// 6. body (plain text fallback) is always populated even in WYSIWYG mode
// ---------------------------------------------------------------------------

- (void)testWYSIWYGAutosaveAlsoStoresPlainBody {
    NSError *err = nil;
    NSString *uuid = [[CPBulletinService sharedService]
                      createDraftWithTitle:@"WYSIWYG Draft" editorMode:@"WYSIWYG" error:&err];
    XCTAssertNotNil(uuid);

    NSString *plain = @"Plain text fallback";
    NSString *html  = @"<p>Plain text fallback</p>";
    [[CPBulletinService sharedService]
     autosaveDraft:uuid title:@"WYSIWYG Draft" summary:nil
      bodyMarkdown:plain bodyHTML:html error:nil];

    NSManagedObjectContext *ctx = [CPCoreDataStack sharedStack].mainContext;
    __block NSString *fetchedBody = nil;
    [ctx performBlockAndWait:^{
        NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"Bulletin"];
        req.predicate = [NSPredicate predicateWithFormat:@"uuid == %@", uuid];
        req.fetchLimit = 1;
        CPBulletin *b = [[ctx executeFetchRequest:req error:nil] firstObject];
        fetchedBody = b.body;
    }];
    XCTAssertEqualObjects(fetchedBody, plain,
                          @"body (plain-text fallback) must be stored alongside bodyHTML");
}

// ---------------------------------------------------------------------------
// 7. Overwriting bodyHTML with nil clears it (Markdown mode takeover)
// ---------------------------------------------------------------------------

- (void)testClearBodyHTMLWhenSwitchingToMarkdown {
    NSError *err = nil;
    NSString *uuid = [[CPBulletinService sharedService]
                      createDraftWithTitle:@"Mode Switch" editorMode:@"WYSIWYG" error:&err];
    XCTAssertNotNil(uuid);

    // First save as WYSIWYG with HTML
    [[CPBulletinService sharedService]
     autosaveDraft:uuid title:@"Mode Switch" summary:nil
      bodyMarkdown:@"Content" bodyHTML:@"<p>Content</p>" error:nil];

    // Then re-save as Markdown (bodyHTML = nil should be respected as "clear")
    // We pass an empty string for bodyHTML to explicitly clear it.
    [[CPBulletinService sharedService]
     autosaveDraft:uuid title:@"Mode Switch" summary:nil
      bodyMarkdown:@"Content" bodyHTML:@"" error:nil];

    NSManagedObjectContext *ctx = [CPCoreDataStack sharedStack].mainContext;
    __block NSString *fetchedHTML = nil;
    [ctx performBlockAndWait:^{
        NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"Bulletin"];
        req.predicate = [NSPredicate predicateWithFormat:@"uuid == %@", uuid];
        req.fetchLimit = 1;
        CPBulletin *b = [[ctx executeFetchRequest:req error:nil] firstObject];
        fetchedHTML = b.bodyHTML;
    }];
    // Empty string passed — stored as empty (not nil, but length 0 = no HTML content)
    XCTAssertEqual(fetchedHTML.length, 0u,
                   @"Passing empty bodyHTML should clear the stored HTML body");
}

@end
