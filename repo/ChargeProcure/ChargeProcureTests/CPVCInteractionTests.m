#import <XCTest/XCTest.h>
#import <UIKit/UIKit.h>
#import "CPAuthService.h"
#import "CPRBACService.h"
#import "CPCoreDataStack.h"
#import "CPTestCoreDataStack.h"
#import "CPAuditLogViewController.h"
#import "CPReportsViewController.h"
#import "CPPricingRuleDetailViewController.h"
#import "CPLoginViewController.h"

// ---------------------------------------------------------------------------
// CPVCInteractionTests
//
// VC-layer interaction tests. These tests instantiate real view controllers,
// trigger viewDidLoad via loadViewIfNeeded, and assert that access-control
// guards and RBAC-driven UI mutations behave correctly — independently of the
// service-layer unit tests that cover the underlying permission logic.
//
//   VCINT-AUDIT-DENY-1:    Non-admin: CPAuditLogViewController leaves `logs` nil
//   VCINT-AUDIT-ALLOW-1:   Admin:     CPAuditLogViewController initialises `logs`
//   VCINT-REPORTS-ALLOW-1: Admin:     CPReportsViewController enables the Generate button
//   VCINT-REPORTS-DENY-1:  Technician: CPReportsViewController disables the Generate button
//   VCINT-PRICING-DENY-1:  Non-admin: CPPricingRuleDetailViewController leaves `scrollView` nil
//   VCINT-PRICING-ALLOW-1: Admin:     CPPricingRuleDetailViewController creates `scrollView`
//   VCINT-LOGIN-1:         CPLoginViewController loads all required UI fields
//   VCINT-LOGIN-2:         Valid admin login yields an active session
//   VCINT-LOGIN-3:         Invalid credentials leave session inactive
// ---------------------------------------------------------------------------

static NSString * const kVCIntTestPass = @"Test1234Pass";

@interface CPVCInteractionTests : XCTestCase
@end

@implementation CPVCInteractionTests

// ---------------------------------------------------------------------------
#pragma mark - Test lifecycle
// ---------------------------------------------------------------------------

- (void)setUp {
    [super setUp];
    [[CPTestCoreDataStack sharedStack] resetAll];
    [[CPAuthService sharedService] logout];

    // Clear all users/roles so seedDefaultUsersWithPassword creates a clean slate.
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [[CPCoreDataStack sharedStack] performBackgroundTask:^(NSManagedObjectContext *ctx) {
        for (NSString *entity in @[@"User", @"Role"]) {
            NSArray *objs = [ctx executeFetchRequest:
                             [NSFetchRequest fetchRequestWithEntityName:entity] error:nil];
            for (NSManagedObject *o in objs) [ctx deleteObject:o];
        }
        [ctx save:nil];
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));

    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"cp_must_change_password_uuids"];
    [[NSUserDefaults standardUserDefaults] synchronize];

    [[CPAuthService sharedService] seedDefaultUsersWithPassword:kVCIntTestPass];
}

- (void)tearDown {
    [[CPAuthService sharedService] logout];
    [[CPTestCoreDataStack sharedStack] resetAll];
    [super tearDown];
}

// ---------------------------------------------------------------------------
#pragma mark - Helpers
// ---------------------------------------------------------------------------

- (void)loginAs:(NSString *)username {
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [[CPAuthService sharedService] loginWithUsername:username
                                           password:kVCIntTestPass
                                         completion:^(BOOL success, NSError *err) {
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
}

/// Loads the VC's view hierarchy by embedding it in a window and calling
/// loadViewIfNeeded.  Returns the VC so callers can inspect state afterward.
- (UIViewController *)loadVC:(UIViewController *)vc {
    UIWindow *window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 375, 812)];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    window.rootViewController = nav;
    [window makeKeyAndVisible];
    [vc loadViewIfNeeded];
    return vc;
}

// ---------------------------------------------------------------------------
#pragma mark - VCINT-AUDIT: CPAuditLogViewController access guard
// ---------------------------------------------------------------------------

/// VCINT-AUDIT-DENY-1
/// A non-admin user (technician) must not receive the logs array — the guard
/// should return before `self.logs` is initialised.
- (void)testAuditLogVCDeniesNonAdmin {
    [self loginAs:@"technician"];

    CPAuditLogViewController *vc = [CPAuditLogViewController new];
    [self loadVC:vc];

    id logs = [vc valueForKey:@"logs"];
    XCTAssertNil(logs,
        @"VCINT-AUDIT-DENY-1: logs must be nil for non-admin; guard must return before setup");
}

/// VCINT-AUDIT-ALLOW-1
/// Admin must pass the guard and have `logs` initialised to an empty mutable
/// array ready for data loading.
- (void)testAuditLogVCAllowsAdmin {
    [self loginAs:@"admin"];

    CPAuditLogViewController *vc = [CPAuditLogViewController new];
    [self loadVC:vc];

    id logs = [vc valueForKey:@"logs"];
    XCTAssertNotNil(logs,
        @"VCINT-AUDIT-ALLOW-1: logs must be non-nil for admin; guard must allow setup");
    XCTAssertTrue([logs isKindOfClass:[NSMutableArray class]],
        @"VCINT-AUDIT-ALLOW-1: logs must be an NSMutableArray");
}

// ---------------------------------------------------------------------------
#pragma mark - VCINT-REPORTS: CPReportsViewController RBAC visibility
// ---------------------------------------------------------------------------

/// VCINT-REPORTS-ALLOW-1
/// Admin holds report.export permission so the Generate button must be enabled.
- (void)testReportsVCEnablesGenerateButtonForAdmin {
    [self loginAs:@"admin"];

    CPReportsViewController *vc = [CPReportsViewController new];
    [self loadVC:vc];

    UIBarButtonItem *btn = vc.navigationItem.rightBarButtonItem;
    XCTAssertNotNil(btn,
        @"VCINT-REPORTS-ALLOW-1: admin must have a Generate button in the nav bar");
    XCTAssertTrue(btn.isEnabled,
        @"VCINT-REPORTS-ALLOW-1: Generate button must be enabled for admin");
}

/// VCINT-REPORTS-DENY-1
/// Site Technician lacks report.export permission so the Generate button must
/// be disabled (hidden via clearColor tint).
- (void)testReportsVCDisablesGenerateButtonForTechnician {
    [self loginAs:@"technician"];

    CPReportsViewController *vc = [CPReportsViewController new];
    [self loadVC:vc];

    UIBarButtonItem *btn = vc.navigationItem.rightBarButtonItem;
    XCTAssertNotNil(btn,
        @"VCINT-REPORTS-DENY-1: button must still be present (hidden, not removed) for technician");
    XCTAssertFalse(btn.isEnabled,
        @"VCINT-REPORTS-DENY-1: Generate button must be disabled for technician (no report.export)");
}

// ---------------------------------------------------------------------------
#pragma mark - VCINT-PRICING: CPPricingRuleDetailViewController access guard
// ---------------------------------------------------------------------------

/// VCINT-PRICING-DENY-1
/// Non-admin (technician) must be blocked by the viewDidLoad guard.  The
/// scrollView is created only after the guard passes, so it must remain nil.
- (void)testPricingDetailVCDeniesNonAdmin {
    [self loginAs:@"technician"];

    CPPricingRuleDetailViewController *vc = [CPPricingRuleDetailViewController new];
    [self loadVC:vc];

    id scrollView = [vc valueForKey:@"scrollView"];
    XCTAssertNil(scrollView,
        @"VCINT-PRICING-DENY-1: scrollView must be nil for non-admin; setupScrollView must not run");
}

/// VCINT-PRICING-ALLOW-1
/// Admin passes the guard and `setupScrollView` runs, creating the scrollView.
- (void)testPricingDetailVCAllowsAdmin {
    [self loginAs:@"admin"];

    CPPricingRuleDetailViewController *vc = [CPPricingRuleDetailViewController new];
    [self loadVC:vc];

    id scrollView = [vc valueForKey:@"scrollView"];
    XCTAssertNotNil(scrollView,
        @"VCINT-PRICING-ALLOW-1: scrollView must be created for admin; setupScrollView must run");
}

// ---------------------------------------------------------------------------
#pragma mark - VCINT-LOGIN: CPLoginViewController structural and session tests
// ---------------------------------------------------------------------------

/// VCINT-LOGIN-1
/// CPLoginViewController must load without crashing and wire up all required
/// UI fields (username / password fields, login button).
- (void)testLoginVCLoadsRequiredFields {
    [[CPAuthService sharedService] logout];

    CPLoginViewController *vc = [CPLoginViewController new];
    [self loadVC:vc];

    id usernameField = [vc valueForKey:@"usernameField"];
    id passwordField = [vc valueForKey:@"passwordField"];
    id loginButton   = [vc valueForKey:@"loginButton"];

    XCTAssertNotNil(usernameField,
        @"VCINT-LOGIN-1: usernameField must be created in buildUI");
    XCTAssertNotNil(passwordField,
        @"VCINT-LOGIN-1: passwordField must be created in buildUI");
    XCTAssertNotNil(loginButton,
        @"VCINT-LOGIN-1: loginButton must be created in buildUI");
}

/// VCINT-LOGIN-2
/// A successful login with known admin credentials must produce an active
/// session (currentUserID non-nil).  The VC delegates auth to CPAuthService;
/// this test validates the session contract the VC relies on.
- (void)testValidLoginProducesActiveSession {
    [[CPAuthService sharedService] logout];
    XCTAssertNil([CPAuthService sharedService].currentUserID,
        @"VCINT-LOGIN-2: precondition — no active session before login");

    [self loginAs:@"admin"];

    XCTAssertNotNil([CPAuthService sharedService].currentUserID,
        @"VCINT-LOGIN-2: successful admin login must produce a non-nil currentUserID");
}

/// VCINT-LOGIN-3
/// An invalid password must leave the session inactive (currentUserID nil).
- (void)testInvalidLoginLeavesSessionInactive {
    [[CPAuthService sharedService] logout];

    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block BOOL loginSucceeded = NO;
    [[CPAuthService sharedService]
     loginWithUsername:@"admin"
              password:@"wrongpassword!"
            completion:^(BOOL success, NSError *err) {
        loginSucceeded = success;
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));

    XCTAssertFalse(loginSucceeded,
        @"VCINT-LOGIN-3: login with wrong password must return success=NO");
    XCTAssertNil([CPAuthService sharedService].currentUserID,
        @"VCINT-LOGIN-3: currentUserID must remain nil after a failed login");
}

@end
