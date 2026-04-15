#import <XCTest/XCTest.h>
#import "CPRBACService.h"
#import "CPAuthService.h"
#import "CPCoreDataStack.h"
#import "CPTestCoreDataStack.h"
#import "CPTestDataFactory.h"
#import <CoreData/CoreData.h>

@interface CPRBACServiceTests : XCTestCase
@property (nonatomic, strong) NSManagedObjectContext *ctx;
@end

/// Known password for all test-owned accounts in this suite.
static NSString * const kRBACTestPass = @"Test1234Pass";

@implementation CPRBACServiceTests

- (void)setUp {
    [super setUp];
    [[CPTestCoreDataStack sharedStack] resetAll];
    self.ctx = [CPTestCoreDataStack sharedStack].mainContext;

    // Clear any existing session and wipe the real user store so seeding is fresh.
    [[CPAuthService sharedService] logout];
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [[CPCoreDataStack sharedStack] performBackgroundTask:^(NSManagedObjectContext *ctx) {
        NSArray *users = [ctx executeFetchRequest:[NSFetchRequest fetchRequestWithEntityName:@"User"] error:nil];
        for (NSManagedObject *u in users) [ctx deleteObject:u];
        NSArray *roles = [ctx executeFetchRequest:[NSFetchRequest fetchRequestWithEntityName:@"Role"] error:nil];
        for (NSManagedObject *r in roles) [ctx deleteObject:r];
        [ctx save:nil];
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d removeObjectForKey:@"cp_must_change_password_uuids"];
    [d synchronize];
}

- (void)tearDown {
    [[CPTestCoreDataStack sharedStack] resetAll];
    [[CPAuthService sharedService] logout];
    [super tearDown];
}

// ---------------------------------------------------------------------------
// 1. testAdminHasAllPermissions — admin can perform all actions on all resources
// ---------------------------------------------------------------------------
- (void)testAdminHasAllPermissions {
    // Seed default users which creates the Administrator role with all permissions
    [[CPAuthService sharedService] seedDefaultUsersWithPassword:kRBACTestPass];

    // Login as admin
    XCTestExpectation *loginExp = [self expectationWithDescription:@"adminLogin"];
    [[CPAuthService sharedService] loginWithUsername:@"admin"
                                            password:kRBACTestPass
                                          completion:^(BOOL success, NSError *error) {
        XCTAssertTrue(success, @"Admin login should succeed");
        [loginExp fulfill];
    }];
    [self waitForExpectationsWithTimeout:10 handler:nil];

    // Admin should be able to perform all standard actions on key resources
    NSArray *resources = @[CPResourceCharger, CPResourceProcurement, CPResourceBulletin,
                           CPResourceInvoice, CPResourceWriteOff, CPResourceUser];
    NSArray *actions = @[CPActionRead, CPActionCreate, CPActionUpdate, CPActionDelete, CPActionApprove];

    for (NSString *resource in resources) {
        for (NSString *action in actions) {
            BOOL canDo = [[CPRBACService sharedService]
                          currentUserCanPerform:action onResource:resource];
            XCTAssertTrue(canDo,
                          @"Admin should be able to perform '%@' on '%@'", action, resource);
        }
    }

    [[CPAuthService sharedService] logout];
}

// ---------------------------------------------------------------------------
// 2. testTechnicianCannotApproveInvoice
// ---------------------------------------------------------------------------
- (void)testTechnicianCannotApproveInvoice {
    [[CPAuthService sharedService] seedDefaultUsersWithPassword:kRBACTestPass];

    XCTestExpectation *loginExp = [self expectationWithDescription:@"techLogin"];
    [[CPAuthService sharedService] loginWithUsername:@"technician"
                                            password:kRBACTestPass
                                          completion:^(BOOL success, NSError *error) {
        XCTAssertTrue(success, @"Technician login should succeed");
        [loginExp fulfill];
    }];
    [self waitForExpectationsWithTimeout:10 handler:nil];

    BOOL canApproveInvoice = [[CPRBACService sharedService]
                               currentUserCanPerform:CPActionApprove
                               onResource:CPResourceInvoice];
    XCTAssertFalse(canApproveInvoice,
                   @"Site Technician should NOT be able to approve invoices");

    [[CPAuthService sharedService] logout];
}

// ---------------------------------------------------------------------------
// 3. testFinanceApproverCanApproveWriteOff
// ---------------------------------------------------------------------------
- (void)testFinanceApproverCanApproveWriteOff {
    [[CPAuthService sharedService] seedDefaultUsersWithPassword:kRBACTestPass];

    XCTestExpectation *loginExp = [self expectationWithDescription:@"financeLogin"];
    [[CPAuthService sharedService] loginWithUsername:@"finance"
                                            password:kRBACTestPass
                                          completion:^(BOOL success, NSError *error) {
        XCTAssertTrue(success, @"Finance login should succeed");
        [loginExp fulfill];
    }];
    [self waitForExpectationsWithTimeout:10 handler:nil];

    BOOL canApproveWriteOff = [[CPRBACService sharedService]
                                currentUserCanPerform:CPActionApprove
                                onResource:CPResourceWriteOff];
    XCTAssertTrue(canApproveWriteOff,
                  @"Finance Approver should be able to approve write-offs");

    [[CPAuthService sharedService] logout];
}

// ---------------------------------------------------------------------------
// 4. testGrantPermissionWorks — grant then check returns YES
// ---------------------------------------------------------------------------
- (void)testGrantPermissionWorks {
    [[CPAuthService sharedService] seedDefaultUsersWithPassword:kRBACTestPass];

    // Login as technician (doesn't have delete on Bulletin)
    XCTestExpectation *loginExp = [self expectationWithDescription:@"techLogin"];
    [[CPAuthService sharedService] loginWithUsername:@"technician"
                                            password:kRBACTestPass
                                          completion:^(BOOL success, NSError *error) {
        [loginExp fulfill];
    }];
    [self waitForExpectationsWithTimeout:10 handler:nil];

    // Verify technician cannot delete bulletins initially
    NSString *techUserID = [CPAuthService sharedService].currentUserID;
    XCTAssertNotNil(techUserID, @"Technician should be logged in");

    BOOL canDeleteBefore = [[CPRBACService sharedService]
                             userID:techUserID
                             canPerform:CPActionDelete
                             onResource:CPResourceBulletin];
    XCTAssertFalse(canDeleteBefore, @"Technician should not be able to delete bulletins before grant");

    // Grant the permission
    NSError *grantErr = nil;
    BOOL granted = [[CPRBACService sharedService]
                    grantPermission:CPActionDelete
                    onResource:CPResourceBulletin
                    toRole:@"Site Technician"
                    error:&grantErr];
    XCTAssertTrue(granted, @"Grant should succeed");
    XCTAssertNil(grantErr, @"No error expected on grant");

    // Check permission again — should now be YES
    BOOL canDeleteAfter = [[CPRBACService sharedService]
                            userID:techUserID
                            canPerform:CPActionDelete
                            onResource:CPResourceBulletin];
    XCTAssertTrue(canDeleteAfter,
                  @"Technician should be able to delete bulletins after permission grant");

    [[CPAuthService sharedService] logout];
}

// ---------------------------------------------------------------------------
// 5. testRevokePermissionWorks — revoke then check returns NO
// ---------------------------------------------------------------------------
- (void)testRevokePermissionWorks {
    [[CPAuthService sharedService] seedDefaultUsersWithPassword:kRBACTestPass];

    // Login as finance approver (has approve on Invoice)
    XCTestExpectation *loginExp = [self expectationWithDescription:@"financeLogin"];
    [[CPAuthService sharedService] loginWithUsername:@"finance"
                                            password:kRBACTestPass
                                          completion:^(BOOL success, NSError *error) {
        [loginExp fulfill];
    }];
    [self waitForExpectationsWithTimeout:10 handler:nil];

    NSString *financeUserID = [CPAuthService sharedService].currentUserID;
    XCTAssertNotNil(financeUserID, @"Finance user should be logged in");

    // Verify can approve invoice before revoke
    BOOL canApproveBefore = [[CPRBACService sharedService]
                              userID:financeUserID
                              canPerform:CPActionApprove
                              onResource:CPResourceInvoice];
    XCTAssertTrue(canApproveBefore, @"Finance approver should be able to approve invoices before revoke");

    // Revoke the permission
    NSError *revokeErr = nil;
    BOOL revoked = [[CPRBACService sharedService]
                    revokePermission:CPActionApprove
                    onResource:CPResourceInvoice
                    fromRole:@"Finance Approver"
                    error:&revokeErr];
    XCTAssertTrue(revoked, @"Revoke should succeed");
    XCTAssertNil(revokeErr, @"No error expected on revoke");

    // Check permission again — should now be NO
    BOOL canApproveAfter = [[CPRBACService sharedService]
                             userID:financeUserID
                             canPerform:CPActionApprove
                             onResource:CPResourceInvoice];
    XCTAssertFalse(canApproveAfter,
                   @"Finance approver should NOT be able to approve invoices after revoke");

    [[CPAuthService sharedService] logout];
}

// ---------------------------------------------------------------------------
// 6. testCacheInvalidatedAfterRevoke — cache reflects revoked permission immediately
// ---------------------------------------------------------------------------
- (void)testCacheInvalidatedAfterRevoke {
    [[CPAuthService sharedService] seedDefaultUsersWithPassword:kRBACTestPass];

    // Login as admin
    XCTestExpectation *loginExp = [self expectationWithDescription:@"adminLogin"];
    [[CPAuthService sharedService] loginWithUsername:@"admin"
                                            password:kRBACTestPass
                                          completion:^(BOOL success, NSError *error) {
        [loginExp fulfill];
    }];
    [self waitForExpectationsWithTimeout:10 handler:nil];

    NSString *adminUserID = [CPAuthService sharedService].currentUserID;
    XCTAssertNotNil(adminUserID, @"Admin should be logged in");

    // Prime the cache: check a permission to put it in NSCache
    BOOL hasExportBefore = [[CPRBACService sharedService]
                             userID:adminUserID
                             canPerform:CPActionExport
                             onResource:CPResourceReport];
    XCTAssertTrue(hasExportBefore, @"Admin should initially be able to export reports");

    // Revoke the export permission from Administrator
    NSError *revokeErr = nil;
    [[CPRBACService sharedService]
     revokePermission:CPActionExport
     onResource:CPResourceReport
     fromRole:@"Administrator"
     error:&revokeErr];

    // The cache should be invalidated immediately — next check should see revoked state
    BOOL hasExportAfter = [[CPRBACService sharedService]
                            userID:adminUserID
                            canPerform:CPActionExport
                            onResource:CPResourceReport];
    XCTAssertFalse(hasExportAfter,
                   @"Cache should be invalidated after revoke; export should be denied immediately");

    [[CPAuthService sharedService] logout];
}

@end
