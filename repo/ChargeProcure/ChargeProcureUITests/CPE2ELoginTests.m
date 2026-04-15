#import <XCTest/XCTest.h>

// ---------------------------------------------------------------------------
// CPE2ELoginTests
//
// End-to-end UI automation tests for the login flow.  The app is launched
// with UI_TESTING=1 which causes AppDelegate to:
//   • use an in-memory Core Data store (clean slate every launch)
//   • seed admin/technician/finance accounts with password "Test1234Pass"
//   • clear the forced-password-rotation flag so tests reach the main UI
//   • suppress the first-run bootstrap credential alert
//
//   E2E-LOGIN-1: Valid admin credentials → tab bar appears
//   E2E-LOGIN-2: Wrong password keeps the login screen (no tab bar)
//   E2E-LOGIN-3: Leaving both fields empty shakes the button, no transition
//   E2E-LOGIN-4: Valid technician credentials → tab bar appears
// ---------------------------------------------------------------------------

static NSString * const kUITestPassword = @"Test1234Pass";

@interface CPE2ELoginTests : XCTestCase
@property (nonatomic, strong) XCUIApplication *app;
@end

@implementation CPE2ELoginTests

- (void)setUp {
    [super setUp];
    self.continueAfterFailure = NO;

    self.app = [[XCUIApplication alloc] init];
    // Signal AppDelegate to use deterministic test credentials and clean state.
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

/// Fills in username + password and taps the Sign In button.
- (void)loginWithUsername:(NSString *)username password:(NSString *)password {
    XCUIElement *usernameField = self.app.textFields[@"loginUsernameField"];
    XCTAssertTrue([usernameField waitForExistenceWithTimeout:5],
        @"Username field must appear within 5 s of app launch");

    [usernameField tap];
    [usernameField typeText:username];

    XCUIElement *passwordField = self.app.secureTextFields[@"loginPasswordField"];
    [passwordField tap];
    [passwordField typeText:password];

    [self.app.buttons[@"loginButton"] tap];
}

// ---------------------------------------------------------------------------
// E2E-LOGIN-1: Valid admin login → tab bar present
// ---------------------------------------------------------------------------

- (void)testE2E_ValidAdminLoginTransitionsToTabBar {
    [self loginWithUsername:@"admin" password:kUITestPassword];

    // After successful login the login screen is replaced by a tab bar.
    XCTAssertTrue([self.app.tabBars.firstMatch waitForExistenceWithTimeout:6],
        @"E2E-LOGIN-1: Tab bar must appear after valid admin login");

    // Login screen must no longer be visible.
    XCTAssertFalse(self.app.buttons[@"loginButton"].exists,
        @"E2E-LOGIN-1: Login button must be gone after successful login");
}

// ---------------------------------------------------------------------------
// E2E-LOGIN-2: Wrong password → stay on login screen
// ---------------------------------------------------------------------------

- (void)testE2E_WrongPasswordStaysOnLoginScreen {
    [self loginWithUsername:@"admin" password:@"WrongPass999!"];

    // Tab bar must NOT appear.
    XCTAssertFalse([self.app.tabBars.firstMatch waitForExistenceWithTimeout:3],
        @"E2E-LOGIN-2: Tab bar must not appear after wrong password");

    // Sign In button must still be visible.
    XCTAssertTrue(self.app.buttons[@"loginButton"].exists,
        @"E2E-LOGIN-2: Login button must still be present after failed login");
}

// ---------------------------------------------------------------------------
// E2E-LOGIN-3: Empty credentials → button shakes, no transition
// ---------------------------------------------------------------------------

- (void)testE2E_EmptyCredentialsTapsShakeWithoutTransition {
    // Tap login without entering any text.
    XCUIElement *loginBtn = self.app.buttons[@"loginButton"];
    XCTAssertTrue([loginBtn waitForExistenceWithTimeout:5]);
    [loginBtn tap];

    // Tab bar must not appear.
    XCTAssertFalse([self.app.tabBars.firstMatch waitForExistenceWithTimeout:2],
        @"E2E-LOGIN-3: Empty credentials must not transition to main app");

    // Login button must still be present.
    XCTAssertTrue(loginBtn.exists,
        @"E2E-LOGIN-3: Login button must still be visible after empty-credential tap");
}

// ---------------------------------------------------------------------------
// E2E-LOGIN-4: Valid technician login → tab bar present
// ---------------------------------------------------------------------------

- (void)testE2E_ValidTechnicianLoginTransitionsToTabBar {
    [self loginWithUsername:@"technician" password:kUITestPassword];

    XCTAssertTrue([self.app.tabBars.firstMatch waitForExistenceWithTimeout:6],
        @"E2E-LOGIN-4: Tab bar must appear after valid technician login");
}

@end
