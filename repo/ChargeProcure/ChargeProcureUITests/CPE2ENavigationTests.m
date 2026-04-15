#import <XCTest/XCTest.h>

// ---------------------------------------------------------------------------
// CPE2ENavigationTests
//
// End-to-end UI automation tests for tab-bar navigation and role-based
// tab visibility.  Launched with UI_TESTING=1 — see CPE2ELoginTests.m for
// the full seeding/clean-state contract.
//
//   E2E-NAV-1:  Admin sees Dashboard tab after login
//   E2E-NAV-2:  Admin sees Chargers tab after login
//   E2E-NAV-3:  Admin taps Chargers tab — Chargers navigation title visible
//   E2E-NAV-4:  Technician sees Chargers tab (role allowed)
//   E2E-NAV-5:  Finance Approver does NOT see Chargers tab (role denied)
//   E2E-NAV-6:  Dashboard is the default selected tab after login
// ---------------------------------------------------------------------------

static NSString * const kUITestPassword = @"Test1234Pass";

@interface CPE2ENavigationTests : XCTestCase
@property (nonatomic, strong) XCUIApplication *app;
@end

@implementation CPE2ENavigationTests

- (void)setUp {
    [super setUp];
    self.continueAfterFailure = NO;

    self.app = [[XCUIApplication alloc] init];
    self.app.launchEnvironment = @{@"UI_TESTING": @"1"};
    [self.app launch];
}

- (void)tearDown {
    [self.app terminate];
    [super tearDown];
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

- (void)loginAs:(NSString *)username {
    XCUIElement *usernameField = self.app.textFields[@"loginUsernameField"];
    XCTAssertTrue([usernameField waitForExistenceWithTimeout:5]);
    [usernameField tap];
    [usernameField typeText:username];

    XCUIElement *passwordField = self.app.secureTextFields[@"loginPasswordField"];
    [passwordField tap];
    [passwordField typeText:kUITestPassword];

    [self.app.buttons[@"loginButton"] tap];

    // Wait for tab bar to confirm successful login before tests begin.
    XCTAssertTrue([self.app.tabBars.firstMatch waitForExistenceWithTimeout:6],
        @"Tab bar must appear after login to run navigation tests");
}

- (XCUIElement *)tabBarButtonNamed:(NSString *)title {
    return self.app.tabBars.firstMatch.buttons[title];
}

// ---------------------------------------------------------------------------
// E2E-NAV-1: Admin — Dashboard tab present after login
// ---------------------------------------------------------------------------

- (void)testE2E_AdminSesDashboardTab {
    [self loginAs:@"admin"];
    XCTAssertTrue([self tabBarButtonNamed:@"Dashboard"].exists,
        @"E2E-NAV-1: Dashboard tab must be present after admin login");
}

// ---------------------------------------------------------------------------
// E2E-NAV-2: Admin — Chargers tab present (admin has charger permission)
// ---------------------------------------------------------------------------

- (void)testE2E_AdminSesChargersTab {
    [self loginAs:@"admin"];
    XCTAssertTrue([self tabBarButtonNamed:@"Chargers"].exists,
        @"E2E-NAV-2: Chargers tab must be present for admin");
}

// ---------------------------------------------------------------------------
// E2E-NAV-3: Admin taps Chargers — navigation title becomes "Chargers"
// ---------------------------------------------------------------------------

- (void)testE2E_AdminTapChargerTabShowsChargerList {
    [self loginAs:@"admin"];

    XCUIElement *chargerTab = [self tabBarButtonNamed:@"Chargers"];
    XCTAssertTrue(chargerTab.exists);
    [chargerTab tap];

    // After tapping the Chargers tab the navigation bar title should
    // reflect the Charger List view controller.
    XCUIElement *navTitle = self.app.navigationBars[@"Chargers"].firstMatch;
    XCTAssertTrue([navTitle waitForExistenceWithTimeout:4],
        @"E2E-NAV-3: Navigation bar titled 'Chargers' must appear after tapping Chargers tab");
}

// ---------------------------------------------------------------------------
// E2E-NAV-4: Technician — Chargers tab visible (technician has charger access)
// ---------------------------------------------------------------------------

- (void)testE2E_TechnicianSesChargersTab {
    [self loginAs:@"technician"];
    XCTAssertTrue([self tabBarButtonNamed:@"Chargers"].exists,
        @"E2E-NAV-4: Chargers tab must be visible for Site Technician");
}

// ---------------------------------------------------------------------------
// E2E-NAV-5: Finance Approver — Chargers tab NOT visible (no charger perms)
// ---------------------------------------------------------------------------

- (void)testE2E_FinanceApproverDoesNotSeeChargersTab {
    [self loginAs:@"finance"];

    // Finance Approver does not have charger.read / charger.execute, so the
    // CPTabBarController must not include a Chargers tab.
    XCTAssertFalse([self tabBarButtonNamed:@"Chargers"].exists,
        @"E2E-NAV-5: Chargers tab must NOT be present for Finance Approver");
}

// ---------------------------------------------------------------------------
// E2E-NAV-6: Dashboard is the initially selected tab after login
// ---------------------------------------------------------------------------

- (void)testE2E_DashboardIsDefaultSelectedTab {
    [self loginAs:@"admin"];

    // The first navigation bar visible after login must be "Dashboard".
    XCUIElement *dashNav = self.app.navigationBars[@"Dashboard"].firstMatch;
    XCTAssertTrue([dashNav waitForExistenceWithTimeout:4],
        @"E2E-NAV-6: Dashboard navigation bar must be visible on first login — it is the default tab");
}

@end
