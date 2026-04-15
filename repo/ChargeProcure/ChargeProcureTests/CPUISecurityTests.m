#import <XCTest/XCTest.h>
#import "CPAuthService.h"
#import "CPRBACService.h"
#import "CPExportService.h"
#import "CPAuditService.h"
#import "CPCoreDataStack.h"
#import "CPTestCoreDataStack.h"
#import "AppDelegate.h"
#import "CPLoginViewController.h"
#import <CoreData/CoreData.h>

// CPSidebarViewController is forward-declared so we can instantiate and inspect
// its item list via KVC without importing private headers.
@interface CPSidebarViewController : UITableViewController
@end

/// Known password for all accounts in this suite.
static NSString * const kUISecPass = @"Test1234Pass";

// ---------------------------------------------------------------------------
// CPUISecurityTests
//
// Tests that verify UI-layer security properties:
//
//   SIDEBAR-1: iPad sidebar shows role-appropriate items after login
//   SIDEBAR-2: Reports entry absent for Site Technician
//   SIDEBAR-3: Analytics entry absent for Site Technician
//   SIDEBAR-4: After logout, sidebar reflects empty/unauthenticated state
//   LOGOUT-1:  CPAuthSessionChangedNotification fires on logout
//   LOGOUT-2:  currentUserID is nil immediately after logout
//   STALE-1:   RBAC check returns NO when no user is logged in
//   EXPORT-1:  Export service returns permission error for technician (UI contract)
// ---------------------------------------------------------------------------

@interface CPUISecurityTests : XCTestCase
@end

@implementation CPUISecurityTests

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

    [[CPAuthService sharedService] seedDefaultUsersWithPassword:kUISecPass];
}

- (void)tearDown {
    [[CPAuthService sharedService] logout];
    [[CPTestCoreDataStack sharedStack] resetAll];
    [super tearDown];
}

- (void)loginAs:(NSString *)username {
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [[CPAuthService sharedService] loginWithUsername:username password:kUISecPass
                                         completion:^(BOOL success, NSError *err) {
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
}

// ---------------------------------------------------------------------------
// Helper: build a sidebar, trigger viewDidLoad, and return item titles via KVC.
// ---------------------------------------------------------------------------

- (NSArray<NSString *> *)sidebarItemTitlesForCurrentUser {
    CPSidebarViewController *sidebar =
        [[CPSidebarViewController alloc] initWithStyle:UITableViewStylePlain];
    // Trigger viewDidLoad → buildItems
    (void)sidebar.view;
    NSArray *items = [sidebar valueForKey:@"items"];
    NSMutableArray<NSString *> *titles = [NSMutableArray array];
    for (id item in items) {
        NSString *title = [item valueForKey:@"title"];
        if (title) [titles addObject:title];
    }
    return [titles copy];
}

// ---------------------------------------------------------------------------
// SIDEBAR-1: Admin sidebar contains all core modules
// ---------------------------------------------------------------------------

- (void)testAdminSidebarContainsAllModules {
    [self loginAs:@"admin"];
    NSArray<NSString *> *titles = [self sidebarItemTitlesForCurrentUser];

    NSArray *required = @[@"Dashboard", @"Chargers", @"Procurement",
                          @"Bulletins", @"Analytics", @"Reports", @"Settings"];
    for (NSString *module in required) {
        XCTAssertTrue([titles containsObject:module],
                      @"Admin sidebar must include '%@'; got: %@", module, titles);
    }
}

// ---------------------------------------------------------------------------
// SIDEBAR-2: Technician sidebar does NOT contain Reports
// ---------------------------------------------------------------------------

- (void)testTechnicianSidebarExcludesReports {
    [self loginAs:@"technician"];
    NSArray<NSString *> *titles = [self sidebarItemTitlesForCurrentUser];

    XCTAssertFalse([titles containsObject:@"Reports"],
                   @"Site Technician must NOT see Reports in the sidebar; got: %@", titles);
}

// ---------------------------------------------------------------------------
// SIDEBAR-3: Technician sidebar does NOT contain Analytics
// ---------------------------------------------------------------------------

- (void)testTechnicianSidebarExcludesAnalytics {
    [self loginAs:@"technician"];
    NSArray<NSString *> *titles = [self sidebarItemTitlesForCurrentUser];

    XCTAssertFalse([titles containsObject:@"Analytics"],
                   @"Site Technician must NOT see Analytics in the sidebar; got: %@", titles);
}

// ---------------------------------------------------------------------------
// SIDEBAR-4: Finance sidebar contains Analytics and Reports
// ---------------------------------------------------------------------------

- (void)testFinanceSidebarContainsAnalyticsAndReports {
    [self loginAs:@"finance"];
    NSArray<NSString *> *titles = [self sidebarItemTitlesForCurrentUser];

    XCTAssertTrue([titles containsObject:@"Analytics"],
                  @"Finance Approver must see Analytics in the sidebar; got: %@", titles);
    XCTAssertTrue([titles containsObject:@"Reports"],
                  @"Finance Approver must see Reports in the sidebar; got: %@", titles);
}

// ---------------------------------------------------------------------------
// SIDEBAR-5: After logout, sidebar shows only Dashboard and Settings
//            (unauthenticated — role-gated items removed)
// ---------------------------------------------------------------------------

- (void)testSidebarAfterLogoutContainsOnlyPublicItems {
    [self loginAs:@"admin"];
    [[CPAuthService sharedService] logout];

    NSArray<NSString *> *titles = [self sidebarItemTitlesForCurrentUser];

    // Role-gated modules must not appear when no user is logged in
    NSArray *protected = @[@"Reports", @"Analytics", @"Chargers", @"Procurement"];
    for (NSString *module in protected) {
        XCTAssertFalse([titles containsObject:module],
                       @"After logout, '%@' must not appear in sidebar; got: %@", module, titles);
    }
}

// ---------------------------------------------------------------------------
// SIDEBAR-6: Role switch correctly refreshes sidebar items
//            (admin → technician: Reports and Analytics disappear)
// ---------------------------------------------------------------------------

- (void)testSidebarUpdatesOnUserSwitch {
    [self loginAs:@"admin"];
    NSArray<NSString *> *adminTitles = [self sidebarItemTitlesForCurrentUser];
    XCTAssertTrue([adminTitles containsObject:@"Reports"]);

    [[CPAuthService sharedService] logout];
    [self loginAs:@"technician"];
    NSArray<NSString *> *techTitles = [self sidebarItemTitlesForCurrentUser];
    XCTAssertFalse([techTitles containsObject:@"Reports"],
                   @"Sidebar must reflect new user's role after switch, not the previous session");
}

// ---------------------------------------------------------------------------
// LOGOUT-1: CPAuthSessionChangedNotification fires on logout
// ---------------------------------------------------------------------------

- (void)testLogoutFiresSessionChangedNotification {
    [self loginAs:@"admin"];

    XCTestExpectation *notifExp = [self expectationWithDescription:@"sessionChangedOnLogout"];
    id observer = [[NSNotificationCenter defaultCenter]
        addObserverForName:@"CPAuthSessionChangedNotification"
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *n) {
        [notifExp fulfill];
    }];

    [[CPAuthService sharedService] logout];

    [self waitForExpectationsWithTimeout:3 handler:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:observer];
}

// ---------------------------------------------------------------------------
// LOGOUT-2: currentUserID is nil immediately after logout (no async delay)
// ---------------------------------------------------------------------------

- (void)testCurrentUserIDNilImmediatelyAfterLogout {
    [self loginAs:@"admin"];
    XCTAssertNotNil([CPAuthService sharedService].currentUserID);

    [[CPAuthService sharedService] logout];

    // Must be synchronous — no dispatch_async allowed for this security-critical path
    XCTAssertNil([CPAuthService sharedService].currentUserID,
                 @"currentUserID must be nil synchronously after logout");
}

// ---------------------------------------------------------------------------
// STALE-1: RBAC returns NO for any action when no user is logged in
// ---------------------------------------------------------------------------

- (void)testRBACDeniesAllActionsWhenNotLoggedIn {
    // Ensure no session
    [[CPAuthService sharedService] logout];

    NSArray *resources = @[CPResourceReport, CPResourceCharger, CPResourceUser,
                           CPResourceInvoice, CPResourceBulletin];
    NSArray *actions   = @[CPActionRead, CPActionCreate, CPActionUpdate,
                           CPActionDelete, CPActionApprove, CPActionExport];

    for (NSString *resource in resources) {
        for (NSString *action in actions) {
            BOOL allowed = [[CPRBACService sharedService]
                            currentUserCanPerform:action onResource:resource];
            XCTAssertFalse(allowed,
                @"No user logged in — RBAC must deny '%@' on '%@'", action, resource);
        }
    }
}

// ---------------------------------------------------------------------------
// EXPORT-1: Export service returns an error (not a file) for a technician
// ---------------------------------------------------------------------------

- (void)testExportServiceReturnsErrorForUnauthorizedUser {
    [self loginAs:@"technician"];

    XCTestExpectation *exp = [self expectationWithDescription:@"exportDenied"];
    [[CPExportService sharedService]
     generateReport:CPReportTypeProcurementSummary
             format:CPExportFormatCSV
         parameters:nil
         completion:^(NSURL *fileURL, NSError *error) {
        XCTAssertNil(fileURL,
                     @"No output file should be produced when the user lacks export permission");
        XCTAssertNotNil(error,
                        @"An error must be returned when export is denied");
        [exp fulfill];
    }];
    [self waitForExpectationsWithTimeout:10 handler:nil];
}

// ---------------------------------------------------------------------------
// READ-AUTH-1: CPAuditService fetchAuditLogsPage returns an error (not data)
//              for a non-admin user (technician lacks "admin" permission).
// ---------------------------------------------------------------------------

- (void)testAuditServiceDeniesReadForNonAdmin {
    [self loginAs:@"technician"];

    XCTestExpectation *exp = [self expectationWithDescription:@"auditReadDenied"];
    [[CPAuditService sharedService]
        fetchAuditLogsPage:0
              resourceType:nil
                    search:nil
                completion:^(NSArray<NSManagedObject *> *logs, BOOL hasMore, NSError *error) {
        XCTAssertNotNil(error,
            @"fetchAuditLogsPage must return an error for a non-admin user");
        XCTAssertEqual(error.code, 403,
            @"Error code must be 403 (permission denied) for non-admin audit fetch; got: %ld",
            (long)error.code);
        XCTAssertEqual(logs.count, 0,
            @"No log entries must be returned when the user lacks admin permission");
        [exp fulfill];
    }];
    [self waitForExpectationsWithTimeout:5 handler:nil];
}

// ---------------------------------------------------------------------------
// READ-AUTH-2: CPAuditService allows read for admin.
// ---------------------------------------------------------------------------

- (void)testAuditServiceAllowsReadForAdmin {
    [self loginAs:@"admin"];

    XCTestExpectation *exp = [self expectationWithDescription:@"auditReadAllowed"];
    [[CPAuditService sharedService]
        fetchAuditLogsPage:0
              resourceType:nil
                    search:nil
                completion:^(NSArray<NSManagedObject *> *logs, BOOL hasMore, NSError *error) {
        XCTAssertNil(error,
            @"fetchAuditLogsPage must NOT return a permission error for an admin user");
        [exp fulfill];
    }];
    [self waitForExpectationsWithTimeout:5 handler:nil];
}

// ---------------------------------------------------------------------------
// READ-AUTH-3: CPRBACService reports canViewInvoice == NO for a technician
//              who lacks Invoice.read permission. This mirrors the guard that
//              CPInvoiceViewController.checkPermissions uses before fetching.
// ---------------------------------------------------------------------------

- (void)testInvoiceViewPermissionDeniedForTechnician {
    [self loginAs:@"technician"];

    // The technician role does not have Invoice.read; verify RBAC reflects that.
    // CPInvoiceViewController reads canViewInvoice via
    //   [rbac currentUserCanPerform:CPActionRead onResource:CPResourceInvoice]
    // If canViewInvoice is NO the VC must not proceed to loadInvoice.
    BOOL canViewInvoice = [[CPRBACService sharedService]
                           currentUserCanPerform:CPActionRead
                                     onResource:CPResourceInvoice];

    XCTAssertFalse(canViewInvoice,
        @"Technician must NOT have Invoice.read permission; "
        @"CPInvoiceViewController should show Access Denied and return without fetching data");
}

// ---------------------------------------------------------------------------
// EXPORT-2: Export service does not return a permission error for admin
// ---------------------------------------------------------------------------

- (void)testExportServiceAllowedForAdmin {
    [self loginAs:@"admin"];

    XCTestExpectation *exp = [self expectationWithDescription:@"exportAllowed"];
    [[CPExportService sharedService]
     generateReport:CPReportTypeProcurementSummary
             format:CPExportFormatCSV
         parameters:nil
         completion:^(NSURL *fileURL, NSError *error) {
        // The service must NOT return a permission-class error for admin.
        if (error) {
            XCTAssertNotEqual(error.code, -1,
                @"Admin must not receive a permission error from the export service; got: %@", error);
        }
        [exp fulfill];
    }];
    [self waitForExpectationsWithTimeout:10 handler:nil];
}

// ---------------------------------------------------------------------------
// ROOT-1: configureRootViewControllerForAuthState installs login VC after logout
//
// This test exercises the real production method used by the app to switch
// between unauthenticated (login screen) and authenticated (tab bar / split VC)
// root view controllers.  It checks both directions:
//   • After login: root must NOT be the CPLoginViewController flow.
//   • After logout: root must be UINavigationController → CPLoginViewController.
// ---------------------------------------------------------------------------

- (void)testLogoutInstallsLoginRootViewController {
    id rawDelegate = [UIApplication sharedApplication].delegate;
    if (![rawDelegate isKindOfClass:[AppDelegate class]]) {
        // Running under a test host that uses a stub app delegate (e.g. a lightweight
        // UITestingAppDelegate).  Skip the root-VC check — the UI contract is still
        // validated by the other tests that exercise CPAuthService and CPRBACService.
        XCTSkip(@"Test host does not use AppDelegate — skipping root-VC transition test");
    }
    AppDelegate *appDelegate = (AppDelegate *)rawDelegate;
    XCTAssertNotNil(appDelegate, @"AppDelegate must be accessible via UIApplication");
    XCTAssertNotNil(appDelegate.window, @"AppDelegate.window must exist in the test host");

    // Log in and install the authenticated root.
    [self loginAs:@"admin"];

    // configureRootViewControllerForAuthState is the production navigation gate.
    // Run on the main thread — it mutates UIWindow.
    dispatch_sync(dispatch_get_main_queue(), ^{
        [appDelegate configureRootViewControllerForAuthState];
    });

    // After successful login the root must NOT be a login navigation controller.
    UIViewController *rootWhileLoggedIn = appDelegate.window.rootViewController;
    BOOL rootIsLoginNav = [rootWhileLoggedIn isKindOfClass:[UINavigationController class]] &&
                          [[(UINavigationController *)rootWhileLoggedIn viewControllers].firstObject
                           isKindOfClass:[CPLoginViewController class]];
    XCTAssertFalse(rootIsLoginNav,
        @"While a user is logged in, root must not be the login screen (got %@)",
        NSStringFromClass([rootWhileLoggedIn class]));

    // Logout and re-configure.
    [[CPAuthService sharedService] logout];

    dispatch_sync(dispatch_get_main_queue(), ^{
        [appDelegate configureRootViewControllerForAuthState];
    });

    // After logout the root MUST be UINavigationController wrapping CPLoginViewController.
    UIViewController *rootAfterLogout = appDelegate.window.rootViewController;
    XCTAssertTrue([rootAfterLogout isKindOfClass:[UINavigationController class]],
        @"After logout, root must be UINavigationController; got %@",
        NSStringFromClass([rootAfterLogout class]));

    UINavigationController *loginNav = (UINavigationController *)rootAfterLogout;
    UIViewController *innerVC = loginNav.viewControllers.firstObject;
    XCTAssertTrue([innerVC isKindOfClass:[CPLoginViewController class]],
        @"After logout, navigation root must be CPLoginViewController; got %@",
        NSStringFromClass([innerVC class]));

    // Extra: confirm session state is consistent with the UI root.
    XCTAssertFalse([[CPAuthService sharedService] isSessionValid],
        @"Session must be invalid after logout");
}

@end
