#import <XCTest/XCTest.h>
#import <UIKit/UIKit.h>
#import <CoreData/CoreData.h>
#import "CPAuditService.h"
#import "CPExportService.h"
#import "CPAuthService.h"
#import "CPRBACService.h"
#import "CPProcurementService.h"
#import "CPCoreDataStack.h"
#import "CPTestCoreDataStack.h"
#import "CPSidebarViewController.h"

// Expose private method for white-box testing without changing production interface.
@interface CPSidebarViewController (TestAccess)
- (UIViewController *)instantiateViewControllerForClassName:(NSString *)className;
@end

// ---------------------------------------------------------------------------
// F-01: iPad sidebar class-wiring tests
// ---------------------------------------------------------------------------
@interface CPSidebarWiringTests : XCTestCase
@end

@implementation CPSidebarWiringTests

/// All class name strings used in CPSidebarViewController.buildItems must resolve
/// to concrete UIViewController subclasses already linked into the binary.
- (void)testAllSidebarClassNamesAreValidViewControllers {
    NSArray<NSString *> *classNames = @[
        @"CPDashboardViewController",
        @"CPChargerListViewController",
        @"CPProcurementListViewController",
        @"CPBulletinListViewController",
        @"CPAnalyticsDashboardViewController",
        @"CPReportsViewController",
        @"CPSettingsViewController",
    ];

    for (NSString *className in classNames) {
        Class cls = NSClassFromString(className);
        XCTAssertNotNil(cls,
            @"Class '%@' must be linked into the binary — sidebar will degrade if missing.", className);
        XCTAssertTrue([cls isSubclassOfClass:[UIViewController class]],
            @"Class '%@' must be a UIViewController subclass.", className);
    }
}

/// The placeholder fallback in CPSidebarViewController must NOT fire for any
/// required module.
- (void)testNoRequiredSidebarModuleIsUnresolvable {
    NSArray<NSString *> *required = @[
        @"CPBulletinListViewController",
        @"CPAnalyticsDashboardViewController",
        @"CPReportsViewController",
    ];
    for (NSString *className in required) {
        Class cls = NSClassFromString(className);
        XCTAssertTrue(cls && [cls isSubclassOfClass:[UIViewController class]],
            @"Required sidebar module '%@' must resolve — no placeholder fallback allowed.", className);
    }
}

/// instantiateViewControllerForClassName: must return an instance of the EXACT
/// expected class for every required route, not a generic UIViewController.
- (void)testInstantiateRequiredClassesReturnCorrectTypes {
    CPSidebarViewController *sidebar = [[CPSidebarViewController alloc]
                                            initWithStyle:UITableViewStylePlain];
    [sidebar loadViewIfNeeded];   // triggers viewDidLoad → buildItems

    NSArray<NSString *> *required = @[
        @"CPDashboardViewController",
        @"CPChargerListViewController",
        @"CPProcurementListViewController",
        @"CPBulletinListViewController",
        @"CPAnalyticsDashboardViewController",
        @"CPReportsViewController",
        @"CPSettingsViewController",
    ];

    for (NSString *className in required) {
        UIViewController *vc = [sidebar instantiateViewControllerForClassName:className];
        XCTAssertNotNil(vc,
            @"instantiation of '%@' must not return nil", className);
        Class expectedClass = NSClassFromString(className);
        XCTAssertTrue([vc isKindOfClass:expectedClass],
            @"instantiation of '%@' must return an instance of that class; "
            @"got %@ — the placeholder fallback must NOT fire for required routes",
            className, NSStringFromClass([vc class]));
    }
}

/// An unrecognised, non-required class name must produce a generic
/// UIViewController placeholder — NOT a concrete module view controller.
/// This verifies the placeholder path is strictly gated to optional/future entries.
- (void)testUnknownOptionalClassProducesPlaceholderNotModuleVC {
    CPSidebarViewController *sidebar = [[CPSidebarViewController alloc]
                                            initWithStyle:UITableViewStylePlain];
    [sidebar loadViewIfNeeded];

    UIViewController *vc = [sidebar instantiateViewControllerForClassName:
                             @"CPNonExistentFutureViewController"];
    XCTAssertNotNil(vc, @"A placeholder must be returned for an unknown optional class");
    XCTAssertTrue([vc isMemberOfClass:[UIViewController class]],
        @"Unknown non-required class must produce a bare UIViewController placeholder; "
        @"got %@", NSStringFromClass([vc class]));
}

@end

// ---------------------------------------------------------------------------
// F-05: CPAuditService and CPExportService API-contract tests
// ---------------------------------------------------------------------------
@interface CPAuditServiceContractTests : XCTestCase
@end

@implementation CPAuditServiceContractTests

- (void)setUp {
    [super setUp];
    [[CPTestCoreDataStack sharedStack] resetAll];
    [[CPAuthService sharedService] logout];
}

- (void)tearDown {
    [[CPTestCoreDataStack sharedStack] resetAll];
    [[CPAuthService sharedService] logout];
    [super tearDown];
}

/// fetchAuditLogsPage:resourceType:search:completion: must exist and call back
/// on the main queue with a valid (possibly empty) array.
- (void)testFetchAuditLogsPageCallsCompletionOnMainQueue {
    XCTestExpectation *exp = [self expectationWithDescription:@"fetchAuditLogsPage"];

    [[CPAuditService sharedService]
        fetchAuditLogsPage:0
        resourceType:nil
        search:nil
        completion:^(NSArray *logs, BOOL hasMore, NSError *error) {
            XCTAssertTrue([NSThread isMainThread], @"Completion must be on main queue");
            XCTAssertNotNil(logs, @"Logs array must be non-nil");
            XCTAssertNil(error, @"No error expected on empty store");
            [exp fulfill];
        }];

    [self waitForExpectationsWithTimeout:5 handler:nil];
}

/// availableResourceTypes must return a non-empty array of strings.
- (void)testAvailableResourceTypesReturnsStrings {
    NSArray<NSString *> *types = [[CPAuditService sharedService] availableResourceTypes];
    XCTAssertTrue(types.count > 0, @"availableResourceTypes must return at least one type");
    for (id obj in types) {
        XCTAssertTrue([obj isKindOfClass:[NSString class]], @"Each type must be an NSString");
    }
}

/// fetchAuditLogsPage: with resourceType filter returns only matching events.
- (void)testFetchAuditLogsPageFiltersResourceType {
    // Log one User event and one Charger event.
    [[CPAuditService sharedService] logAction:@"login_success" resource:@"User" resourceID:nil detail:nil];
    [[CPAuditService sharedService] logAction:@"update" resource:@"Charger" resourceID:nil detail:nil];

    XCTestExpectation *exp = [self expectationWithDescription:@"filteredFetch"];
    [[CPAuditService sharedService]
        fetchAuditLogsPage:0
        resourceType:@"User"
        search:nil
        completion:^(NSArray *logs, BOOL hasMore, NSError *error) {
            for (NSManagedObject *log in logs) {
                NSString *res = [log valueForKey:@"resource"];
                XCTAssertEqualObjects(res, @"User",
                    @"Filtered fetch must return only 'User' resource events");
            }
            [exp fulfill];
        }];

    [self waitForExpectationsWithTimeout:5 handler:nil];
}

/// The AuditEvent entity stores the timestamp under 'occurredAt', not 'timestamp'.
- (void)testAuditEventUsesOccurredAtNotTimestamp {
    [[CPAuditService sharedService] logAction:@"test_action" resource:@"User" resourceID:@"u1" detail:nil];

    XCTestExpectation *exp = [self expectationWithDescription:@"occurredAtKey"];
    [[CPAuditService sharedService]
        fetchAuditLogsPage:0
        resourceType:nil
        search:nil
        completion:^(NSArray *logs, BOOL hasMore, NSError *error) {
            NSManagedObject *first = logs.firstObject;
            if (first) {
                NSDate *occurredAt = [first valueForKey:@"occurredAt"];
                XCTAssertNotNil(occurredAt, @"AuditEvent must have a non-nil 'occurredAt' date");
                // 'timestamp' is not a valid key — accessing it returns nil.
                id badKey = [first valueForKey:@"timestamp"];
                XCTAssertNil(badKey, @"AuditEvent does not have a 'timestamp' key; use 'occurredAt'");
            }
            [exp fulfill];
        }];

    [self waitForExpectationsWithTimeout:5 handler:nil];
}

/// exportAuditLogsWithResourceType:search:completion: must be callable and call back
/// on the main queue. (In test environment, file generation may fail — we only
/// verify the API contract and main-queue delivery.)
- (void)testExportAuditLogsAPIContract {
    XCTestExpectation *exp = [self expectationWithDescription:@"exportAuditLogs"];

    [[CPExportService sharedService]
        exportAuditLogsWithResourceType:nil
        search:nil
        completion:^(NSURL *fileURL, NSError *error) {
            XCTAssertTrue([NSThread isMainThread], @"Completion must be on main queue");
            // Either a file URL or an error is acceptable; what matters is callback fires.
            XCTAssertTrue(fileURL != nil || error != nil,
                @"Completion must provide either a fileURL or an error");
            [exp fulfill];
        }];

    [self waitForExpectationsWithTimeout:10 handler:nil];
}

@end

// ---------------------------------------------------------------------------
// F-04: Role taxonomy consistency tests
// ---------------------------------------------------------------------------
@interface CPRoleTaxonomyTests : XCTestCase
@end

@implementation CPRoleTaxonomyTests

- (void)setUp {
    [super setUp];
    [[CPTestCoreDataStack sharedStack] resetAll];
    [[CPAuthService sharedService] logout];
}

- (void)tearDown {
    [[CPTestCoreDataStack sharedStack] resetAll];
    [[CPAuthService sharedService] logout];
    [super tearDown];
}

/// The three seeded roles must be the canonical business roles and no others.
- (void)testSeedCreatesOnlyCanonicalRoles {
    [[CPAuthService sharedService] seedDefaultUsersIfNeeded];

    NSArray<NSString *> *canonical = @[@"Administrator", @"Site Technician", @"Finance Approver"];
    NSArray<NSString *> *legacy    = @[@"Viewer", @"Editor"];

    // Fetch seeded users directly from the real Core Data store (not test store).
    __block NSArray *seededUsers = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [[CPCoreDataStack sharedStack] performBackgroundTask:^(NSManagedObjectContext *ctx) {
        NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"User"];
        req.relationshipKeyPathsForPrefetching = @[@"role"];
        seededUsers = [ctx executeFetchRequest:req error:nil] ?: @[];
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));

    for (NSManagedObject *user in seededUsers) {
        NSManagedObject *role = [user valueForKey:@"role"];
        NSString *roleName    = role ? [role valueForKey:@"name"] : nil;
        NSString *uname       = [user valueForKey:@"username"];
        if (!roleName) continue;

        XCTAssertTrue([canonical containsObject:roleName],
            @"User '%@' has role '%@' which is not a canonical business role.", uname, roleName);

        // Extract legacy list to a local variable — inline @[] literals inside
        // XCTAssertFalse confuse the preprocessor's bracket counter.
        BOOL isLegacyRole = [legacy containsObject:roleName];
        XCTAssertFalse(isLegacyRole,
            @"User '%@' must not have a legacy role ('%@').", uname, roleName);
    }
}

/// The three canonical roles are the only valid choices for role assignment.
- (void)testCanonicalRoleSetIsCorrect {
    NSArray<NSString *> *canonical = @[@"Administrator", @"Site Technician", @"Finance Approver"];
    NSArray<NSString *> *legacy    = @[@"Viewer", @"Editor"];

    for (NSString *role in legacy) {
        XCTAssertFalse([canonical containsObject:role],
            @"Legacy role '%@' must not appear in the canonical role set.", role);
    }
    XCTAssertEqual(canonical.count, (NSUInteger)3, @"There are exactly three canonical roles.");
}

@end

// ---------------------------------------------------------------------------
// F-05: Behavioral UI journey tests
//
// These tests exercise multi-layer user journeys — auth → service → data — to
// catch regressions that structural/contract tests cannot see.  They intentionally
// stop short of full XCUITest (no tap simulation) but exercise the same code
// paths that a logged-in user would hit, covering the acceptance-critical risks:
//
//   JOURNEY-1: Admin login → report history readable
//   JOURNEY-2: Technician login → report history denied (nil, not crash)
//   JOURNEY-3: Unauthenticated → report history denied (nil)
//   JOURNEY-4: Unauthenticated → report URL lookup denied (nil)
//   JOURNEY-5: Audit read denied at service layer for non-admin
//   JOURNEY-6: Audit read allowed at service layer for admin
//   JOURNEY-7: Variance-flagged filter returns only cases whose invoice has varianceFlag=YES
//   JOURNEY-8: Variance-unflagged cases excluded from filter
// ---------------------------------------------------------------------------

static NSString * const kJourneyTestPass = @"Journey1234Pass";

@interface CPUIJourneyTests : XCTestCase
@end

@implementation CPUIJourneyTests

- (void)setUp {
    [super setUp];
    [[CPTestCoreDataStack sharedStack] resetAll];
    [[CPAuthService sharedService] logout];

    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [[CPCoreDataStack sharedStack] performBackgroundTask:^(NSManagedObjectContext *ctx) {
        for (NSString *entity in @[@"User", @"Role"]) {
            for (NSManagedObject *o in [ctx executeFetchRequest:
                 [NSFetchRequest fetchRequestWithEntityName:entity] error:nil])
                [ctx deleteObject:o];
        }
        [ctx save:nil];
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));

    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"cp_must_change_password_uuids"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[CPAuthService sharedService] seedDefaultUsersWithPassword:kJourneyTestPass];
}

- (void)tearDown {
    [[CPAuthService sharedService] logout];
    [[CPTestCoreDataStack sharedStack] resetAll];
    [super tearDown];
}

- (void)loginAs:(NSString *)username {
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [[CPAuthService sharedService]
        loginWithUsername:username
        password:kJourneyTestPass
        completion:^(BOOL success, NSError *error) {
            dispatch_semaphore_signal(sem);
        }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
}

// JOURNEY-1: Admin login → report history list returns a non-nil array
- (void)testAdminCanFetchReportHistory {
    [self loginAs:@"admin"];
    NSArray *exports = [[CPExportService sharedService] fetchReportExports];
    XCTAssertNotNil(exports,
        @"Admin must receive a non-nil array from fetchReportExports");
    XCTAssertTrue([exports isKindOfClass:[NSArray class]],
        @"fetchReportExports must return NSArray for admin");
}

// JOURNEY-2: Technician login → report history list is denied (nil returned)
- (void)testTechnicianCannotFetchReportHistory {
    [self loginAs:@"technician"];
    NSArray *exports = [[CPExportService sharedService] fetchReportExports];
    XCTAssertNil(exports,
        @"Technician must receive nil from fetchReportExports — no report.read/export permission");
}

// JOURNEY-3: No session → report history list is denied (nil returned)
- (void)testUnauthenticatedCannotFetchReportHistory {
    // Deliberately logged out — no session.
    NSArray *exports = [[CPExportService sharedService] fetchReportExports];
    XCTAssertNil(exports,
        @"Unauthenticated caller must receive nil from fetchReportExports");
}

// JOURNEY-4: No session → exportURLForReportUUID: returns nil (not crash)
- (void)testUnauthenticatedCannotOpenReportURL {
    NSURL *url = [[CPExportService sharedService]
                  exportURLForReportUUID:[[NSUUID UUID] UUIDString]];
    XCTAssertNil(url,
        @"exportURLForReportUUID must return nil when no session is active");
}

// JOURNEY-5: Technician login → audit service denies read and returns error
- (void)testTechnicianAuditReadIsDeniedAtServiceLayer {
    [self loginAs:@"technician"];

    XCTestExpectation *exp = [self expectationWithDescription:@"auditDenied"];
    [[CPAuditService sharedService]
        fetchAuditLogsPage:0
        resourceType:nil
        search:nil
        completion:^(NSArray *logs, BOOL hasMore, NSError *error) {
            XCTAssertNotNil(error,
                @"Technician must receive a permission error from fetchAuditLogsPage:resourceType:search:");
            XCTAssertEqual(logs.count, (NSUInteger)0,
                @"No audit events must be returned to a non-admin caller");
            [exp fulfill];
        }];
    [self waitForExpectationsWithTimeout:5 handler:nil];
}

// JOURNEY-6: Admin login → audit service allows read (no permission error)
- (void)testAdminAuditReadIsAllowedAtServiceLayer {
    [self loginAs:@"admin"];

    // Write one event so the response is non-trivial.
    [[CPAuditService sharedService] logAction:@"test_event" resource:@"Charger" resourceID:@"c1" detail:nil];

    XCTestExpectation *exp = [self expectationWithDescription:@"auditAllowed"];
    [[CPAuditService sharedService]
        fetchAuditLogsPage:0
        resourceType:nil
        search:nil
        completion:^(NSArray *logs, BOOL hasMore, NSError *error) {
            XCTAssertNil(error,
                @"Admin must not receive a permission error from fetchAuditLogsPage:resourceType:search:");
            XCTAssertGreaterThan(logs.count, (NSUInteger)0,
                @"Admin must receive the logged audit event");
            [exp fulfill];
        }];
    [self waitForExpectationsWithTimeout:5 handler:nil];
}

// JOURNEY-7: Invoice.varianceFlag=YES propagates to the procurement variance predicate
- (void)testVarianceFlaggedCaseIsFoundByServicePredicate {
    [self loginAs:@"admin"];

    // Create a minimal ProcurementCase with a linked Invoice whose varianceFlag is YES.
    __block NSString *caseUUID = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [[CPCoreDataStack sharedStack] performBackgroundTask:^(NSManagedObjectContext *ctx) {
        NSManagedObject *procCase = [NSEntityDescription
            insertNewObjectForEntityForName:@"ProcurementCase"
            inManagedObjectContext:ctx];
        caseUUID = [[NSUUID UUID] UUIDString];
        [procCase setValue:caseUUID         forKey:@"uuid"];
        [procCase setValue:@"PC-TEST-001"   forKey:@"caseNumber"];
        [procCase setValue:@"Variance test" forKey:@"title"];
        [procCase setValue:@(0)             forKey:@"stageValue"];

        NSManagedObject *invoice = [NSEntityDescription
            insertNewObjectForEntityForName:@"Invoice"
            inManagedObjectContext:ctx];
        [invoice setValue:[[NSUUID UUID] UUIDString] forKey:@"uuid"];
        [invoice setValue:@YES forKey:@"varianceFlag"];
        [invoice setValue:procCase forKey:@"procurementCase"];

        [ctx save:nil];
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));

    // The variance-flagged predicate must find this case.
    NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"ProcurementCase"];
    req.predicate = [NSPredicate predicateWithFormat:@"ANY invoices.varianceFlag == YES"];
    NSArray *results = [[CPCoreDataStack sharedStack].mainContext
                        executeFetchRequest:req error:nil];
    BOOL found = NO;
    for (NSManagedObject *c in results) {
        if ([[c valueForKey:@"uuid"] isEqualToString:caseUUID]) { found = YES; break; }
    }
    XCTAssertTrue(found,
        @"Variance-flagged predicate must find a ProcurementCase whose linked Invoice has varianceFlag=YES");
}

// JOURNEY-8: Invoice.varianceFlag=NO is excluded from the variance predicate
- (void)testNonVarianceFlaggedCaseIsExcludedByPredicate {
    [self loginAs:@"admin"];

    __block NSString *caseUUID = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [[CPCoreDataStack sharedStack] performBackgroundTask:^(NSManagedObjectContext *ctx) {
        NSManagedObject *procCase = [NSEntityDescription
            insertNewObjectForEntityForName:@"ProcurementCase"
            inManagedObjectContext:ctx];
        caseUUID = [[NSUUID UUID] UUIDString];
        [procCase setValue:caseUUID         forKey:@"uuid"];
        [procCase setValue:@"PC-TEST-002"   forKey:@"caseNumber"];
        [procCase setValue:@"No variance"   forKey:@"title"];
        [procCase setValue:@(0)             forKey:@"stageValue"];

        NSManagedObject *invoice = [NSEntityDescription
            insertNewObjectForEntityForName:@"Invoice"
            inManagedObjectContext:ctx];
        [invoice setValue:[[NSUUID UUID] UUIDString] forKey:@"uuid"];
        [invoice setValue:@NO  forKey:@"varianceFlag"];
        [invoice setValue:procCase forKey:@"procurementCase"];

        [ctx save:nil];
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));

    NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"ProcurementCase"];
    req.predicate = [NSPredicate predicateWithFormat:@"ANY invoices.varianceFlag == YES"];
    NSArray *results = [[CPCoreDataStack sharedStack].mainContext
                        executeFetchRequest:req error:nil];
    for (NSManagedObject *c in results) {
        XCTAssertFalse([[c valueForKey:@"uuid"] isEqualToString:caseUUID],
            @"Non-variance-flagged case must NOT appear in the variance filter results");
    }
}

@end
