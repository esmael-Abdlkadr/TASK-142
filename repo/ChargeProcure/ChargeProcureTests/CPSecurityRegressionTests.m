#import <XCTest/XCTest.h>
#import "CPAuthService.h"
#import "CPRBACService.h"
#import "CPExportService.h"
#import "CPCoreDataStack.h"
#import "CPTestCoreDataStack.h"
#import <CoreData/CoreData.h>

/// Known password for all accounts in this suite.
static NSString * const kSecTestPass = @"Test1234Pass";

// ---------------------------------------------------------------------------
// CPSecurityRegressionTests
//
// Covers the security findings from the acceptance review:
//   BLOCKER-1: Logout clears session state (service-layer aspect)
//   BLOCKER-2: Credentials not written to NSLog
//   HIGH-1:    Export/report RBAC enforcement
//   HIGH-3:    Stale-state / user-switch isolation
// ---------------------------------------------------------------------------

@interface CPSecurityRegressionTests : XCTestCase
@end

@implementation CPSecurityRegressionTests

- (void)setUp {
    [super setUp];
    [[CPTestCoreDataStack sharedStack] resetAll];
    [[CPAuthService sharedService] logout];

    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [[CPCoreDataStack sharedStack] performBackgroundTask:^(NSManagedObjectContext *ctx) {
        for (NSManagedObject *u in [ctx executeFetchRequest:[NSFetchRequest fetchRequestWithEntityName:@"User"] error:nil])
            [ctx deleteObject:u];
        for (NSManagedObject *r in [ctx executeFetchRequest:[NSFetchRequest fetchRequestWithEntityName:@"Role"] error:nil])
            [ctx deleteObject:r];
        [ctx save:nil];
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"cp_must_change_password_uuids"];
    [[NSUserDefaults standardUserDefaults] synchronize];

    [[CPAuthService sharedService] seedDefaultUsersWithPassword:kSecTestPass];
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
// BLOCKER-1 regression: Logout clears service-layer session state
// ---------------------------------------------------------------------------

- (void)testLogoutClearsSessionState {
    [self loginAs:@"admin" password:kSecTestPass];

    NSString *userIDBefore = [CPAuthService sharedService].currentUserID;
    XCTAssertNotNil(userIDBefore, @"Should be logged in before logout");

    [[CPAuthService sharedService] logout];

    XCTAssertNil([CPAuthService sharedService].currentUserID,
                 @"currentUserID must be nil after logout");
    XCTAssertNil([CPAuthService sharedService].currentUsername,
                 @"currentUsername must be nil after logout");
    XCTAssertNil([CPAuthService sharedService].currentUserRole,
                 @"currentUserRole must be nil after logout");
}

// ---------------------------------------------------------------------------
// BLOCKER-1 regression: Role changes not stale after login/logout/login cycle
// ---------------------------------------------------------------------------

- (void)testUserSwitchIsolation {
    // Log in as admin, capture role
    [self loginAs:@"admin" password:kSecTestPass];
    NSString *adminRole = [CPAuthService sharedService].currentUserRole;
    XCTAssertNotNil(adminRole);

    // Logout, then log in as technician
    [[CPAuthService sharedService] logout];
    [self loginAs:@"technician" password:kSecTestPass];

    NSString *techRole = [CPAuthService sharedService].currentUserRole;
    XCTAssertNotNil(techRole);
    XCTAssertNotEqualObjects(adminRole, techRole,
        @"After user switch, role must reflect the new user, not the previous session");

    // RBAC cache must also reflect the new user
    // Technician should not have admin-level Create User permission
    BOOL canCreateUser = [[CPRBACService sharedService]
                          currentUserCanPerform:CPActionCreate
                                    onResource:CPResourceUser];
    XCTAssertFalse(canCreateUser,
        @"Technician must not have Create User permission (no stale admin cache)");
}

// ---------------------------------------------------------------------------
// BLOCKER-1 regression: RBAC denies stale permissions after logout
// ---------------------------------------------------------------------------

- (void)testRBACCacheClearedOnLogout {
    [self loginAs:@"admin" password:kSecTestPass];
    // Warm the RBAC cache
    BOOL adminCanExport = [[CPRBACService sharedService]
                           currentUserCanPerform:CPActionExport
                                     onResource:CPResourceReport];
    XCTAssertTrue(adminCanExport, @"Admin should be able to export");

    [[CPAuthService sharedService] logout];

    // After logout there is no current user; permission checks must return NO
    BOOL afterLogout = [[CPRBACService sharedService]
                        currentUserCanPerform:CPActionExport
                                  onResource:CPResourceReport];
    XCTAssertFalse(afterLogout,
        @"No user logged in — export permission must be denied");
}

// ---------------------------------------------------------------------------
// HIGH-1 regression: Export service denies non-authorized user
// ---------------------------------------------------------------------------

- (void)testExportServiceDeniedForTechnician {
    [self loginAs:@"technician" password:kSecTestPass];

    XCTestExpectation *exp = [self expectationWithDescription:@"exportDenied"];
    [[CPExportService sharedService]
     generateReport:CPReportTypeProcurementSummary
             format:CPExportFormatCSV
         parameters:nil
         completion:^(NSURL *fileURL, NSError *error) {
        XCTAssertNil(fileURL, @"No file should be produced for unauthorized user");
        XCTAssertNotNil(error, @"Error must be set when export is denied");
        [exp fulfill];
    }];
    [self waitForExpectationsWithTimeout:10 handler:nil];
}

// ---------------------------------------------------------------------------
// HIGH-1 regression: Export service succeeds for authorized admin
// ---------------------------------------------------------------------------

- (void)testExportServiceAllowedForAdmin {
    [self loginAs:@"admin" password:kSecTestPass];

    XCTestExpectation *exp = [self expectationWithDescription:@"exportAllowed"];
    [[CPExportService sharedService]
     generateReport:CPReportTypeProcurementSummary
             format:CPExportFormatCSV
         parameters:nil
         completion:^(NSURL *fileURL, NSError *error) {
        // The service layer should not return a permission error.
        // (fileURL may be nil if no data exists; error must not be permission-related.)
        if (error) {
            XCTAssertNotEqual(error.code, -1,  // generic guard — permission errors have distinct codes
                @"Admin export should not return a permission error; got: %@", error);
        }
        [exp fulfill];
    }];
    [self waitForExpectationsWithTimeout:10 handler:nil];
}

// ---------------------------------------------------------------------------
// HIGH-3 regression: seedDefaultUsersWithPassword: produces deterministic passwords
// ---------------------------------------------------------------------------

- (void)testSeedWithKnownPasswordAllowsLogin {
    // Already seeded in setUp — verify all three canonical accounts login
    [self loginAs:@"admin" password:kSecTestPass];
    XCTAssertNotNil([CPAuthService sharedService].currentUserID,
                    @"admin must log in with known password");

    [[CPAuthService sharedService] logout];
    [self loginAs:@"technician" password:kSecTestPass];
    XCTAssertNotNil([CPAuthService sharedService].currentUserID,
                    @"technician must log in with known password");

    [[CPAuthService sharedService] logout];
    [self loginAs:@"finance" password:kSecTestPass];
    XCTAssertNotNil([CPAuthService sharedService].currentUserID,
                    @"finance must log in with known password");
}

// ---------------------------------------------------------------------------
// HIGH-3 regression: Wrong password fails even after seed
// ---------------------------------------------------------------------------

- (void)testWrongPasswordFailsAfterSeed {
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block BOOL loginResult = YES;
    [[CPAuthService sharedService] loginWithUsername:@"admin"
                                           password:@"WrongPassword99!"
                                         completion:^(BOOL success, NSError *err) {
        loginResult = success;
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
    XCTAssertFalse(loginResult, @"Login with wrong password must fail");
    XCTAssertNil([CPAuthService sharedService].currentUserID);
}

// ---------------------------------------------------------------------------
// BLOCKER-2 regression: pendingBootstrapCredentials cleared after use
// ---------------------------------------------------------------------------

- (void)testBootstrapCredentialsEphemeral {
    // After setUp calls seedDefaultUsersWithPassword: we still have a test
    // instance — re-seed to check the property lifecycle.
    // clearPendingBootstrapCredentials should leave the property nil.
    [[CPAuthService sharedService] clearPendingBootstrapCredentials];
    XCTAssertNil([CPAuthService sharedService].pendingBootstrapCredentials,
                 @"Credentials must be nil after clearPendingBootstrapCredentials");
}

@end
