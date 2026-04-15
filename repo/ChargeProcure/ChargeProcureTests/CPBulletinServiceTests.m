#import <XCTest/XCTest.h>
#import "CPBulletinService.h"
#import "CPAttachmentService.h"
#import "CPTestCoreDataStack.h"
#import "CPTestDataFactory.h"
#import <CoreData/CoreData.h>

@interface CPBulletinServiceTests : XCTestCase
@property (nonatomic, strong) NSManagedObjectContext *ctx;
@end

@implementation CPBulletinServiceTests

- (void)setUp {
    [super setUp];
    [[CPTestCoreDataStack sharedStack] resetAll];
    self.ctx = [CPTestCoreDataStack sharedStack].mainContext;
}

- (void)tearDown {
    [[CPTestCoreDataStack sharedStack] resetAll];
    [super tearDown];
}

// ---------------------------------------------------------------------------
// Helper: create a draft and autosave with content
// ---------------------------------------------------------------------------
- (NSString *)createDraftWithTitle:(NSString *)title body:(NSString *)body summary:(NSString *)summary {
    NSError *createErr = nil;
    NSString *uuid = [[CPBulletinService sharedService] createDraftWithTitle:title
                                                                  editorMode:@"Markdown"
                                                                       error:&createErr];
    if (!uuid) return nil;

    if (body || summary) {
        [[CPBulletinService sharedService]
         autosaveDraft:uuid
         title:title
         summary:summary
         bodyMarkdown:body
         bodyHTML:nil
         error:nil];

        // Brief pause for background task
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            dispatch_semaphore_signal(sem);
        });
        dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
    }
    return uuid;
}

// Helper: wait for a brief background task
- (void)waitBriefly {
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        dispatch_semaphore_signal(sem);
    });
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC));
}

// ---------------------------------------------------------------------------
// 1. testCreateDraft — new draft has status=Draft
// ---------------------------------------------------------------------------
- (void)testCreateDraft {
    NSError *err = nil;
    NSString *uuid = [[CPBulletinService sharedService] createDraftWithTitle:@"Test Draft Bulletin"
                                                                  editorMode:@"Markdown"
                                                                       error:&err];
    XCTAssertNotNil(uuid, @"createDraft should return a non-nil UUID");
    XCTAssertNil(err, @"No error expected when creating a draft");

    // Fetch and verify draft status
    [self waitBriefly];
    NSArray *drafts = [[CPBulletinService sharedService]
                       fetchBulletinsWithStatus:@"Draft" offset:0 limit:20];

    BOOL found = NO;
    for (id bulletin in drafts) {
        if ([[bulletin valueForKey:@"uuid"] isEqualToString:uuid]) {
            found = YES;
            // CPBulletinStatusDraft == 0
            XCTAssertEqual([[bulletin valueForKey:@"statusValue"] integerValue], 0,
                           @"New draft should have statusValue == 0 (Draft)");
            break;
        }
    }
    XCTAssertTrue(found, @"New draft should appear in fetchBulletinsWithStatus:'Draft'");
}

// ---------------------------------------------------------------------------
// 2. testAutosaveDoesNotCreateVersion — autosave updates body but no BulletinVersion added
// ---------------------------------------------------------------------------
- (void)testAutosaveDoesNotCreateVersion {
    NSString *uuid = [self createDraftWithTitle:@"Autosave Test" body:nil summary:nil];
    XCTAssertNotNil(uuid);

    NSError *err = nil;
    BOOL saved = [[CPBulletinService sharedService]
                  autosaveDraft:uuid
                  title:@"Autosave Test — Updated Title"
                  summary:@"A short summary."
                  bodyMarkdown:@"## Updated Body\nSome autosaved content."
                  bodyHTML:nil
                  error:&err];

    XCTAssertTrue(saved, @"Autosave should return YES");
    XCTAssertNil(err, @"No error expected on autosave");

    [self waitBriefly];

    // Verify NO BulletinVersion was created for this bulletin
    NSArray *versions = [[CPBulletinService sharedService] fetchVersionsForBulletin:uuid];
    XCTAssertEqual(versions.count, (NSUInteger)0,
                   @"Autosave must NOT create any BulletinVersion entries");
}

// ---------------------------------------------------------------------------
// 3. testPublishCreatesBulletinVersion — publish creates immutable BulletinVersion
// ---------------------------------------------------------------------------
- (void)testPublishCreatesBulletinVersion {
    NSString *uuid = [self createDraftWithTitle:@"Publish Version Test"
                                           body:@"# Content\nBody text."
                                        summary:@"Publish summary."];
    XCTAssertNotNil(uuid);

    NSError *pubErr = nil;
    BOOL published = [[CPBulletinService sharedService]
                      publishBulletin:uuid
                      publishAt:nil
                      unpublishAt:nil
                      recommendationWeight:50
                      isPinned:NO
                      error:&pubErr];

    XCTAssertTrue(published, @"publishBulletin should succeed");
    XCTAssertNil(pubErr, @"No error expected on publish");

    // Wait for background save to complete
    [self waitBriefly];

    NSArray *versions = [[CPBulletinService sharedService] fetchVersionsForBulletin:uuid];
    XCTAssertGreaterThanOrEqual(versions.count, (NSUInteger)1,
                                @"Publishing should create at least one BulletinVersion snapshot");

    id version = versions.firstObject;
    XCTAssertNotNil([version valueForKey:@"uuid"],
                    @"BulletinVersion should have a UUID");
    XCTAssertEqualObjects([version valueForKey:@"bulletinID"], uuid,
                          @"BulletinVersion.bulletinID should match the parent bulletin");
    XCTAssertNotNil([version valueForKey:@"versionNumber"],
                    @"BulletinVersion should have a versionNumber");
}

// ---------------------------------------------------------------------------
// 4. testSummaryTooLongRejected — summary > 280 chars returns CPBulletinErrorSummaryTooLong
// ---------------------------------------------------------------------------
- (void)testSummaryTooLongRejected {
    NSString *uuid = [self createDraftWithTitle:@"Long Summary Test" body:nil summary:nil];
    XCTAssertNotNil(uuid);

    // Build a 281-character summary
    NSString *longSummary = [@"" stringByPaddingToLength:281 withString:@"X" startingAtIndex:0];
    XCTAssertEqual(longSummary.length, (NSUInteger)281);

    NSError *err = nil;
    BOOL saved = [[CPBulletinService sharedService]
                  autosaveDraft:uuid
                  title:@"Long Summary Test"
                  summary:longSummary
                  bodyMarkdown:nil
                  bodyHTML:nil
                  error:&err];

    XCTAssertFalse(saved, @"Autosave should fail when summary exceeds 280 characters");
    XCTAssertNotNil(err, @"An error should be returned for an oversized summary");
    XCTAssertEqual(err.code, CPBulletinErrorSummaryTooLong,
                   @"Error code should be CPBulletinErrorSummaryTooLong");
}

// ---------------------------------------------------------------------------
// 5. testSummaryExactly280Accepted — exactly 280 chars succeeds
// ---------------------------------------------------------------------------
- (void)testSummaryExactly280Accepted {
    NSString *uuid = [self createDraftWithTitle:@"Exact Summary Test" body:nil summary:nil];
    XCTAssertNotNil(uuid);

    // Build exactly a 280-character summary
    NSString *exactSummary = [@"" stringByPaddingToLength:280 withString:@"Y" startingAtIndex:0];
    XCTAssertEqual(exactSummary.length, (NSUInteger)280);

    NSError *err = nil;
    BOOL saved = [[CPBulletinService sharedService]
                  autosaveDraft:uuid
                  title:@"Exact Summary Test"
                  summary:exactSummary
                  bodyMarkdown:nil
                  bodyHTML:nil
                  error:&err];

    XCTAssertTrue(saved, @"Autosave should succeed with exactly 280-character summary");
    XCTAssertNil(err, @"No error expected for exactly 280-char summary");
}

// ---------------------------------------------------------------------------
// 6. testInvalidWeightRejected — weight 101 returns CPBulletinErrorInvalidWeight
// ---------------------------------------------------------------------------
- (void)testInvalidWeightRejected {
    NSString *uuid = [self createDraftWithTitle:@"Invalid Weight Test" body:nil summary:nil];
    XCTAssertNotNil(uuid);

    NSError *err = nil;
    BOOL published = [[CPBulletinService sharedService]
                      publishBulletin:uuid
                      publishAt:nil
                      unpublishAt:nil
                      recommendationWeight:101
                      isPinned:NO
                      error:&err];

    XCTAssertFalse(published, @"Publishing with weight=101 should fail");
    XCTAssertNotNil(err, @"An error should be returned for weight > 100");
    XCTAssertEqual(err.code, CPBulletinErrorInvalidWeight,
                   @"Error code should be CPBulletinErrorInvalidWeight (3002)");
}

// ---------------------------------------------------------------------------
// 7. testRestoreVersion — restoreVersion copies fields back to bulletin as draft
// ---------------------------------------------------------------------------
- (void)testRestoreVersion {
    NSString *uuid = [self createDraftWithTitle:@"Restore Version Test"
                                           body:@"# Original Content"
                                        summary:@"Original summary"];
    XCTAssertNotNil(uuid);

    // Publish to create a version snapshot
    NSError *pubErr = nil;
    BOOL published = [[CPBulletinService sharedService]
                      publishBulletin:uuid
                      publishAt:nil
                      unpublishAt:nil
                      recommendationWeight:10
                      isPinned:NO
                      error:&pubErr];
    XCTAssertTrue(published, @"Publish should succeed");
    [self waitBriefly];

    NSArray *versions = [[CPBulletinService sharedService] fetchVersionsForBulletin:uuid];
    if (versions.count == 0) {
        XCTSkip(@"No BulletinVersion created — skipping restoreVersion test");
        return;
    }

    NSString *versionUUID = [[versions firstObject] valueForKey:@"uuid"];
    XCTAssertNotNil(versionUUID);

    NSError *restoreErr = nil;
    BOOL restored = [[CPBulletinService sharedService]
                     restoreVersion:versionUUID
                     toBulletin:uuid
                     error:&restoreErr];

    XCTAssertTrue(restored, @"restoreVersion should succeed");
    XCTAssertNil(restoreErr, @"No error expected on version restore");

    [self waitBriefly];

    // After restore, the bulletin should be in Draft status
    NSArray *drafts = [[CPBulletinService sharedService]
                       fetchBulletinsWithStatus:@"Draft" offset:0 limit:20];
    BOOL foundAsDraft = NO;
    for (id bulletin in drafts) {
        if ([[bulletin valueForKey:@"uuid"] isEqualToString:uuid]) {
            foundAsDraft = YES;
            XCTAssertEqual([[bulletin valueForKey:@"statusValue"] integerValue], 0,
                           @"Restored bulletin should have Draft status (0)");
            break;
        }
    }
    XCTAssertTrue(foundAsDraft, @"After restore, bulletin should appear in Draft status");
}

// ---------------------------------------------------------------------------
// 8. testScheduledPublish — processScheduledBulletins publishes bulletin with past publishAt
// ---------------------------------------------------------------------------
- (void)testScheduledPublish {
    NSString *uuid = [self createDraftWithTitle:@"Scheduled Publish Test"
                                           body:@"Body"
                                        summary:@"Scheduled summary"];
    XCTAssertNotNil(uuid);

    // publishAt = 60 seconds in the past → should be treated as immediate (Published)
    NSDate *pastPublishAt = [NSDate dateWithTimeIntervalSinceNow:-60];
    NSError *pubErr = nil;
    BOOL result = [[CPBulletinService sharedService]
                   publishBulletin:uuid
                   publishAt:pastPublishAt
                   unpublishAt:nil
                   recommendationWeight:0
                   isPinned:NO
                   error:&pubErr];

    XCTAssertTrue(result, @"Publish with past publishAt should succeed");
    XCTAssertNil(pubErr);

    [self waitBriefly];

    // The service treats past publishAt as immediate → status should be Published
    NSArray *publishedList = [[CPBulletinService sharedService]
                              fetchBulletinsWithStatus:@"Published" offset:0 limit:20];
    BOOL isPublished = NO;
    for (id bulletin in publishedList) {
        if ([[bulletin valueForKey:@"uuid"] isEqualToString:uuid]) {
            isPublished = YES;
            break;
        }
    }
    XCTAssertTrue(isPublished,
                  @"Bulletin with past publishAt should be immediately Published");

    // processScheduledBulletins should handle this gracefully (no crash, no duplicate)
    [[CPBulletinService sharedService] processScheduledBulletins];
    [self waitBriefly];

    // Still published, not duplicated
    NSArray *afterProcess = [[CPBulletinService sharedService]
                             fetchBulletinsWithStatus:@"Published" offset:0 limit:20];
    NSInteger countForUUID = 0;
    for (id bulletin in afterProcess) {
        if ([[bulletin valueForKey:@"uuid"] isEqualToString:uuid]) {
            countForUUID++;
        }
    }
    XCTAssertEqual(countForUUID, 1, @"Bulletin should not be duplicated by processScheduledBulletins");
}

// ---------------------------------------------------------------------------
// 9. testScheduledUnpublish — processScheduledBulletins archives with past unpublishAt
// ---------------------------------------------------------------------------
- (void)testScheduledUnpublish {
    NSString *uuid = [self createDraftWithTitle:@"Scheduled Unpublish Test"
                                           body:@"Body"
                                        summary:@"Unpublish summary"];
    XCTAssertNotNil(uuid);

    // Publish immediately with an unpublishAt = 60 seconds ago
    NSDate *pastUnpublishAt = [NSDate dateWithTimeIntervalSinceNow:-60];
    NSError *pubErr = nil;
    BOOL published = [[CPBulletinService sharedService]
                      publishBulletin:uuid
                      publishAt:nil
                      unpublishAt:pastUnpublishAt
                      recommendationWeight:0
                      isPinned:NO
                      error:&pubErr];

    XCTAssertTrue(published, @"Publish with past unpublishAt should succeed");
    XCTAssertNil(pubErr);

    [self waitBriefly];

    // Call processScheduledBulletins — should archive this bulletin
    [[CPBulletinService sharedService] processScheduledBulletins];

    [self waitBriefly];

    // Verify it is now Archived
    NSArray *archivedList = [[CPBulletinService sharedService]
                             fetchBulletinsWithStatus:@"Archived" offset:0 limit:20];
    BOOL isArchived = NO;
    for (id bulletin in archivedList) {
        if ([[bulletin valueForKey:@"uuid"] isEqualToString:uuid]) {
            isArchived = YES;
            XCTAssertEqual([[bulletin valueForKey:@"statusValue"] integerValue], 3,
                           @"Archived bulletin should have statusValue == 3");
            break;
        }
    }
    XCTAssertTrue(isArchived,
                  @"Bulletin with past unpublishAt should be archived by processScheduledBulletins");
}

// ---------------------------------------------------------------------------
// 10. testVersionHistoryRestore — publish creates version; restore reverts to Draft
// ---------------------------------------------------------------------------
- (void)testVersionHistoryRestore {
    NSString *uuid = [self createDraftWithTitle:@"Version Restore Test"
                                           body:@"Original body"
                                        summary:@"Original summary"];
    XCTAssertNotNil(uuid);

    // Publish — this creates a BulletinVersion snapshot
    NSError *pubErr = nil;
    BOOL published = [[CPBulletinService sharedService]
                      publishBulletin:uuid
                      publishAt:nil
                      unpublishAt:nil
                      recommendationWeight:5
                      isPinned:NO
                      error:&pubErr];
    XCTAssertTrue(published, @"Publish should succeed. Error: %@", pubErr);
    [self waitBriefly];

    // Fetch the version created at publish time
    NSArray *versions = [[CPBulletinService sharedService] fetchVersionsForBulletin:uuid];
    XCTAssertGreaterThan(versions.count, 0, @"At least one BulletinVersion should exist after publish");

    NSManagedObject *ver = versions.firstObject;
    NSString *versionUUID = [ver valueForKey:@"uuid"];
    XCTAssertNotNil(versionUUID, @"Version must have a UUID");

    // Restore to that version — should reset bulletin to Draft
    NSError *restoreErr = nil;
    BOOL restored = [[CPBulletinService sharedService]
                     restoreVersion:versionUUID
                         toBulletin:uuid
                              error:&restoreErr];
    XCTAssertTrue(restored, @"restoreVersion:toBulletin: should succeed. Error: %@", restoreErr);
    [self waitBriefly];

    // Verify bulletin is now a Draft
    NSArray *drafts = [[CPBulletinService sharedService]
                       fetchBulletinsWithStatus:@"Draft" offset:0 limit:20];
    BOOL foundAsDraft = NO;
    for (id b in drafts) {
        if ([[b valueForKey:@"uuid"] isEqualToString:uuid]) {
            foundAsDraft = YES;
            XCTAssertEqual([[b valueForKey:@"statusValue"] integerValue], 0,
                           @"Restored bulletin statusValue should be 0 (Draft)");
            break;
        }
    }
    XCTAssertTrue(foundAsDraft, @"Restored bulletin should appear in Draft list");
}

// ---------------------------------------------------------------------------
// 11. testWeeklyCleanupDeletesStaleDraft — draft older than 90 days is deleted
// ---------------------------------------------------------------------------
- (void)testWeeklyCleanupDeletesStaleDraft {
    NSString *uuid = [self createDraftWithTitle:@"Stale Draft For Cleanup"
                                           body:@"Old body"
                                        summary:@"Old summary"];
    XCTAssertNotNil(uuid);

    // Age the draft to 91 days ago
    NSManagedObjectContext *realCtx = [[CPBulletinService sharedService] mainContext];
    [realCtx performBlockAndWait:^{
        NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"Bulletin"];
        req.predicate = [NSPredicate predicateWithFormat:@"uuid == %@", uuid];
        req.fetchLimit = 1;
        NSArray *results = [realCtx executeFetchRequest:req error:nil];
        NSManagedObject *bulletin = results.firstObject;
        if (bulletin) {
            NSDate *oldDate = [NSDate dateWithTimeIntervalSinceNow:-(91 * 24 * 3600)];
            [bulletin setValue:oldDate forKey:@"createdAt"];
            [realCtx save:nil];
        }
    }];

    // Run the cleanup
    [[CPAttachmentService sharedService] runWeeklyCleanup];
    [self waitBriefly];

    // Verify the bulletin is gone
    NSArray *drafts = [[CPBulletinService sharedService]
                       fetchBulletinsWithStatus:@"Draft" offset:0 limit:100];
    BOOL stillExists = NO;
    for (id b in drafts) {
        if ([[b valueForKey:@"uuid"] isEqualToString:uuid]) {
            stillExists = YES;
            break;
        }
    }
    XCTAssertFalse(stillExists,
                   @"Stale unpinned draft (91 days old) should be deleted by runWeeklyCleanup");
}

// ---------------------------------------------------------------------------
// 12. testWeeklyCleanupPreservesPinnedDraft — pinned old draft is NOT deleted
// ---------------------------------------------------------------------------
- (void)testWeeklyCleanupPreservesPinnedDraft {
    NSString *uuid = [self createDraftWithTitle:@"Pinned Old Draft"
                                           body:@"Pinned body"
                                        summary:@"Pinned summary"];
    XCTAssertNotNil(uuid);

    // Age and pin the draft
    NSManagedObjectContext *realCtx = [[CPBulletinService sharedService] mainContext];
    [realCtx performBlockAndWait:^{
        NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"Bulletin"];
        req.predicate = [NSPredicate predicateWithFormat:@"uuid == %@", uuid];
        req.fetchLimit = 1;
        NSArray *results = [realCtx executeFetchRequest:req error:nil];
        NSManagedObject *bulletin = results.firstObject;
        if (bulletin) {
            NSDate *oldDate = [NSDate dateWithTimeIntervalSinceNow:-(91 * 24 * 3600)];
            [bulletin setValue:oldDate forKey:@"createdAt"];
            [bulletin setValue:@YES forKey:@"isPinned"];
            [realCtx save:nil];
        }
    }];

    // Run the cleanup
    [[CPAttachmentService sharedService] runWeeklyCleanup];
    [self waitBriefly];

    // Verify the pinned draft is preserved
    NSArray *drafts = [[CPBulletinService sharedService]
                       fetchBulletinsWithStatus:@"Draft" offset:0 limit:100];
    BOOL stillExists = NO;
    for (id b in drafts) {
        if ([[b valueForKey:@"uuid"] isEqualToString:uuid]) {
            stillExists = YES;
            break;
        }
    }
    XCTAssertTrue(stillExists,
                  @"Pinned draft should be preserved by runWeeklyCleanup even when old");
}

// ---------------------------------------------------------------------------
// 13. testCoverImagePathPersistedOnBulletin — setCoverImagePath stores path on entity
// ---------------------------------------------------------------------------
- (void)testCoverImagePathPersistedOnBulletin {
    NSString *uuid = [self createDraftWithTitle:@"Cover Image Test"
                                           body:@"Body"
                                        summary:@"Summary"];
    XCTAssertNotNil(uuid);

    NSString *fakePath = @"/var/mobile/Documents/bulletin_test_cover.jpg";
    [[CPBulletinService sharedService] setCoverImagePath:fakePath forBulletinUUID:uuid];

    [self waitBriefly];

    // Verify coverImagePath was stored
    NSManagedObjectContext *ctx = [[CPBulletinService sharedService] mainContext];
    __block NSString *storedPath = nil;
    [ctx performBlockAndWait:^{
        NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"Bulletin"];
        req.predicate = [NSPredicate predicateWithFormat:@"uuid == %@", uuid];
        req.fetchLimit = 1;
        NSArray *results = [ctx executeFetchRequest:req error:nil];
        storedPath = [[results firstObject] valueForKey:@"coverImagePath"];
    }];
    XCTAssertEqualObjects(storedPath, fakePath,
                          @"coverImagePath on entity must match the path passed to setCoverImagePath:forBulletinUUID:");
}

@end
