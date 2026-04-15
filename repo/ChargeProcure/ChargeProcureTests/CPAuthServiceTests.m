#import <XCTest/XCTest.h>
#import "CPAuthService.h"
#import "CPCoreDataStack.h"
#import "CPTestCoreDataStack.h"
#import "CPTestDataFactory.h"
#import <CoreData/CoreData.h>

// ---------------------------------------------------------------------------
// Category to swap the shared stack to the in-memory test stack.
// CPAuthService uses [CPCoreDataStack sharedStack] internally; we forward
// that call to CPTestCoreDataStack by swizzling at test time.
// ---------------------------------------------------------------------------

@interface CPAuthServiceTests : XCTestCase
@property (nonatomic, strong) NSManagedObjectContext *ctx;
@end

@implementation CPAuthServiceTests

- (void)setUp {
    [super setUp];
    // Wipe all data before every test
    [[CPTestCoreDataStack sharedStack] resetAll];
    self.ctx = [CPTestCoreDataStack sharedStack].mainContext;

    // Delete all User entities from the REAL on-disk store so that
    // seedDefaultUsersIfNeeded always starts from a clean slate and
    // lockout state from prior tests never bleeds into the next one.
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [[CPCoreDataStack sharedStack] performBackgroundTask:^(NSManagedObjectContext *ctx) {
        NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"User"];
        NSArray *users = [ctx executeFetchRequest:req error:nil];
        for (NSManagedObject *u in users) [ctx deleteObject:u];
        [ctx save:nil];
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));

    // Clear any persisted session and bootstrap state so tests start clean.
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeObjectForKey:@"cp_current_user_id"];
    [defaults removeObjectForKey:@"cp_current_username"];
    [defaults removeObjectForKey:@"cp_current_user_role"];
    [defaults removeObjectForKey:@"cp_must_change_password_uuids"];
    [defaults synchronize];
}

- (void)tearDown {
    [[CPAuthService sharedService] logout];
    [[CPTestCoreDataStack sharedStack] resetAll];
    [super tearDown];
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Known password used for test-owned accounts (does not appear in seed logic).
static NSString * const kTestPassword = @"TestPass1234";

/// Creates a user with a known password via CPAuthService and returns the password.
/// Uses the shared (real) Core Data stack so login calls can find the user.
- (void)createTestUserWithUsername:(NSString *)username role:(NSString *)role {
    NSError *error = nil;
    BOOL ok = [[CPAuthService sharedService] createUserWithUsername:username
                                                          password:kTestPassword
                                                          roleName:role
                                                             error:&error];
    XCTAssertTrue(ok,
        @"Test-user creation for '%@' must succeed; error: %@", username, error);
}

// ---------------------------------------------------------------------------
// 1. testValidPasswordAccepted
// ---------------------------------------------------------------------------
- (void)testValidPasswordAccepted {
    CPAuthService *svc = [CPAuthService sharedService];
    NSError *error = nil;
    BOOL valid = [svc validatePassword:@"Admin1234Pass" error:&error];
    XCTAssertTrue(valid, @"'Admin1234Pass' should pass validation");
    XCTAssertNil(error, @"No error expected for a valid password");
}

// ---------------------------------------------------------------------------
// 2. testPasswordTooShortRejected
// ---------------------------------------------------------------------------
- (void)testPasswordTooShortRejected {
    CPAuthService *svc = [CPAuthService sharedService];
    NSError *error = nil;
    BOOL valid = [svc validatePassword:@"abc123" error:&error];
    XCTAssertFalse(valid, @"'abc123' is too short and should fail");
    XCTAssertNotNil(error, @"An error should be returned");
    XCTAssertEqual(error.code, CPAuthErrorPasswordTooShort,
                   @"Error code should be CPAuthErrorPasswordTooShort");
}

// ---------------------------------------------------------------------------
// 3. testPasswordNoDigitRejected
// ---------------------------------------------------------------------------
- (void)testPasswordNoDigitRejected {
    CPAuthService *svc = [CPAuthService sharedService];
    NSError *error = nil;
    BOOL valid = [svc validatePassword:@"AdminPassword" error:&error];
    XCTAssertFalse(valid, @"'AdminPassword' has no digit and should fail");
    XCTAssertNotNil(error, @"An error should be returned");
    XCTAssertEqual(error.code, CPAuthErrorPasswordNoNumber,
                   @"Error code should be CPAuthErrorPasswordNoNumber");
}

// ---------------------------------------------------------------------------
// 4. testLoginSuccess — create a test user and login with correct credentials
// ---------------------------------------------------------------------------
- (void)testLoginSuccess {
    [self createTestUserWithUsername:@"testadmin" role:@"Administrator"];

    XCTestExpectation *expectation = [self expectationWithDescription:@"loginSuccess"];
    [[CPAuthService sharedService] loginWithUsername:@"testadmin"
                                            password:kTestPassword
                                          completion:^(BOOL success, NSError *error) {
        XCTAssertTrue(success, @"Login with correct credentials should succeed");
        XCTAssertNil(error, @"No error expected on success");
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:10 handler:nil];

    [[CPAuthService sharedService] logout];
}

// ---------------------------------------------------------------------------
// 5. testLoginWrongPassword — wrong password fails and failedAttempts increments
// ---------------------------------------------------------------------------
- (void)testLoginWrongPassword {
    [self createTestUserWithUsername:@"testuser_wp" role:@"Administrator"];

    XCTestExpectation *expectation = [self expectationWithDescription:@"wrongPassword"];
    [[CPAuthService sharedService] loginWithUsername:@"testuser_wp"
                                            password:@"WrongPassword1"
                                          completion:^(BOOL success, NSError *error) {
        XCTAssertFalse(success, @"Login with wrong password should fail");
        XCTAssertNotNil(error, @"Error should be returned for wrong password");
        XCTAssertEqual(error.code, CPAuthErrorInvalidCredentials,
                       @"Error code should be CPAuthErrorInvalidCredentials");
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:10 handler:nil];
}

// ---------------------------------------------------------------------------
// 6. testLoginLockoutAfterFiveFailures
// ---------------------------------------------------------------------------
- (void)testLoginLockoutAfterFiveFailures {
    [self createTestUserWithUsername:@"testuser_lockout" role:@"Site Technician"];

    // Submit 5 wrong-password attempts
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block NSInteger callCount = 0;
    __block NSInteger lockoutCount = 0;

    for (int i = 0; i < 5; i++) {
        [[CPAuthService sharedService] loginWithUsername:@"testuser_lockout"
                                                password:@"WrongPass999"
                                              completion:^(BOOL success, NSError *error) {
            XCTAssertFalse(success);
            if (error.code == CPAuthErrorLockedOut) {
                lockoutCount++;
            }
            callCount++;
            if (callCount == 5) {
                dispatch_semaphore_signal(sem);
            }
        }];
    }
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC));

    // After 5 failures, at least the last attempt should yield a lockout error
    XCTAssertGreaterThanOrEqual(lockoutCount, 1,
        @"At least one attempt should return CPAuthErrorLockedOut after 5 failures");
}

// ---------------------------------------------------------------------------
// 7. testLockedOutAccountRefused
// ---------------------------------------------------------------------------
- (void)testLockedOutAccountRefused {
    [self createTestUserWithUsername:@"testuser_lor" role:@"Finance Approver"];

    // Trigger 5 consecutive wrong-password attempts to trip the lockout threshold.
    XCTestExpectation *exp1 = [self expectationWithDescription:@"firstLoginFail"];
    [[CPAuthService sharedService] loginWithUsername:@"testuser_lor"
                                            password:@"WrongPass1"
                                          completion:^(BOOL s, NSError *e) {
        [exp1 fulfill];
    }];
    [self waitForExpectationsWithTimeout:10 handler:nil];

    dispatch_group_t group = dispatch_group_create();
    for (int i = 0; i < 4; i++) {
        dispatch_group_enter(group);
        [[CPAuthService sharedService] loginWithUsername:@"testuser_lor"
                                                password:@"WrongPass1"
                                              completion:^(BOOL s, NSError *e) {
            dispatch_group_leave(group);
        }];
    }
    dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC));

    // After 5 failures even the correct password is blocked.
    XCTestExpectation *exp2 = [self expectationWithDescription:@"lockedOut"];
    [[CPAuthService sharedService] loginWithUsername:@"testuser_lor"
                                            password:kTestPassword
                                          completion:^(BOOL success, NSError *error) {
        XCTAssertFalse(success, @"Locked-out account should be refused");
        BOOL isLockedOutError = (error.code == CPAuthErrorLockedOut ||
                                 error.code == CPAuthErrorInvalidCredentials);
        XCTAssertTrue(isLockedOutError,
                      @"Error should be locked-out or invalid credentials, got: %ld", (long)error.code);
        [exp2 fulfill];
    }];
    [self waitForExpectationsWithTimeout:10 handler:nil];
}

// ---------------------------------------------------------------------------
// 8. testLockoutExpiresAfterCooldown
// ---------------------------------------------------------------------------
- (void)testLockoutExpiresAfterCooldown {
    [self createTestUserWithUsername:@"testuser_expiry" role:@"Administrator"];

    // Lock the user via 5 wrong-password attempts.
    dispatch_semaphore_t lockSem = dispatch_semaphore_create(0);
    __block NSInteger doneCount = 0;
    for (int i = 0; i < 5; i++) {
        [[CPAuthService sharedService] loginWithUsername:@"testuser_expiry"
                                                password:@"BadPassword1"
                                              completion:^(BOOL s, NSError *e) {
            doneCount++;
            if (doneCount == 5) {
                dispatch_semaphore_signal(lockSem);
            }
        }];
    }
    dispatch_semaphore_wait(lockSem, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC));

    // Verify account is now locked.
    XCTestExpectation *expLocked = [self expectationWithDescription:@"checkLocked"];
    [[CPAuthService sharedService] loginWithUsername:@"testuser_expiry"
                                            password:kTestPassword
                                          completion:^(BOOL success, NSError *error) {
        XCTAssertFalse(success, @"Account should be locked");
        [expLocked fulfill];
    }];
    [self waitForExpectationsWithTimeout:10 handler:nil];

    // Simulate lockout expiry by writing a past lockoutUntil into Core Data.
    CPCoreDataStack *stack = [CPCoreDataStack sharedStack];
    dispatch_semaphore_t expirySem = dispatch_semaphore_create(0);
    [stack performBackgroundTask:^(NSManagedObjectContext *bgCtx) {
        NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"User"];
        req.predicate  = [NSPredicate predicateWithFormat:@"username == %@", @"testuser_expiry"];
        req.fetchLimit = 1;
        NSArray *users = [bgCtx executeFetchRequest:req error:nil];
        NSManagedObject *user = users.firstObject;
        if (user) {
            [user setValue:[NSDate dateWithTimeIntervalSinceNow:-120] forKey:@"lockoutUntil"];
            [user setValue:@(0) forKey:@"failedAttempts"];
            [bgCtx save:nil];
        }
        dispatch_semaphore_signal(expirySem);
    }];
    dispatch_semaphore_wait(expirySem, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));

    // After expiry, login with the correct password must succeed.
    XCTestExpectation *expAfterExpiry = [self expectationWithDescription:@"loginAfterExpiry"];
    [[CPAuthService sharedService] loginWithUsername:@"testuser_expiry"
                                            password:kTestPassword
                                          completion:^(BOOL success, NSError *error) {
        XCTAssertTrue(success, @"Login should succeed after lockout has expired");
        XCTAssertNil(error, @"No error expected after lockout expiry");
        [expAfterExpiry fulfill];
    }];
    [self waitForExpectationsWithTimeout:10 handler:nil];

    [[CPAuthService sharedService] logout];
}

// ---------------------------------------------------------------------------
// 9. testSuccessfulLoginResetsFailedAttempts
// ---------------------------------------------------------------------------
- (void)testSuccessfulLoginResetsFailedAttempts {
    [self createTestUserWithUsername:@"testuser_reset" role:@"Site Technician"];

    // One wrong attempt
    XCTestExpectation *exp1 = [self expectationWithDescription:@"wrongAttempt"];
    [[CPAuthService sharedService] loginWithUsername:@"testuser_reset"
                                            password:@"WrongPass1"
                                          completion:^(BOOL s, NSError *e) {
        XCTAssertFalse(s);
        [exp1 fulfill];
    }];
    [self waitForExpectationsWithTimeout:10 handler:nil];

    // Successful login with correct password.
    XCTestExpectation *exp2 = [self expectationWithDescription:@"successLogin"];
    [[CPAuthService sharedService] loginWithUsername:@"testuser_reset"
                                            password:kTestPassword
                                          completion:^(BOOL success, NSError *error) {
        XCTAssertTrue(success, @"Correct credentials should succeed");
        XCTAssertNil(error);
        [exp2 fulfill];
    }];
    [self waitForExpectationsWithTimeout:10 handler:nil];

    XCTAssertTrue([CPAuthService sharedService].isSessionValid,
                  @"Session should be valid after successful login");
    XCTAssertEqualObjects([CPAuthService sharedService].currentUsername,
                          @"testuser_reset",
                          @"currentUsername should match");

    [[CPAuthService sharedService] logout];
}

// ---------------------------------------------------------------------------
// 10. testBiometricNotAvailableOnSimulator
// ---------------------------------------------------------------------------
- (void)testBiometricNotAvailableOnSimulator {
    // On the simulator, biometrics are not available; the service should return an error.
    XCTestExpectation *exp = [self expectationWithDescription:@"biometricUnavailable"];
    [[CPAuthService sharedService] authenticateWithBiometrics:^(BOOL success, NSError *error) {
        XCTAssertFalse(success, @"Biometric should not succeed on simulator");
        XCTAssertNotNil(error, @"An error should be returned when biometrics unavailable");
        // Error code is either BiometricUnavailable (no stored username) or BiometricFailed
        BOOL validCode = (error.code == CPAuthErrorBiometricUnavailable ||
                          error.code == CPAuthErrorBiometricFailed ||
                          error.code == CPAuthErrorUserNotFound);
        XCTAssertTrue(validCode,
                      @"Error code should be a biometric-related code, got: %ld", (long)error.code);
        [exp fulfill];
    }];
    [self waitForExpectationsWithTimeout:10 handler:nil];
}

// ---------------------------------------------------------------------------
// 11. testSeedDefaultUsersCreatesThreeUsers
// ---------------------------------------------------------------------------
- (void)testSeedDefaultUsersCreatesThreeUsers {
    BOOL seeded = [[CPAuthService sharedService] seedDefaultUsersIfNeeded];
    XCTAssertTrue(seeded, @"seedDefaultUsersIfNeeded should return YES on a fresh store");

    // Verify exactly three users were created via Core Data (no known password needed).
    __block NSArray *users = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [[CPCoreDataStack sharedStack] performBackgroundTask:^(NSManagedObjectContext *ctx) {
        NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"User"];
        req.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"username" ascending:YES]];
        users = [ctx executeFetchRequest:req error:nil] ?: @[];
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));

    XCTAssertEqual(users.count, (NSUInteger)3,
                   @"Exactly three users must be seeded: admin, technician, finance");

    // Verify all three UUIDs are registered for mandatory password rotation.
    NSArray *mustChange = [[NSUserDefaults standardUserDefaults]
                               arrayForKey:@"cp_must_change_password_uuids"];
    XCTAssertEqual(mustChange.count, (NSUInteger)3,
                   @"All three seeded accounts must be flagged for forced password rotation");

    // Verify the expected usernames are present.
    NSArray<NSString *> *expectedNames = @[@"admin", @"finance", @"technician"]; // sorted
    for (NSUInteger i = 0; i < MIN(users.count, expectedNames.count); i++) {
        NSString *uname = [users[i] valueForKey:@"username"];
        XCTAssertEqualObjects(uname, expectedNames[i],
            @"Seeded username at index %lu should be '%@', got '%@'",
            (unsigned long)i, expectedNames[i], uname);
    }
}

// ---------------------------------------------------------------------------
// 12. testSeedDefaultUsersIdempotent
// ---------------------------------------------------------------------------
- (void)testSeedDefaultUsersIdempotent {
    BOOL seeded1 = [[CPAuthService sharedService] seedDefaultUsersIfNeeded];
    XCTAssertTrue(seeded1, @"First seed should return YES");

    BOOL seeded2 = [[CPAuthService sharedService] seedDefaultUsersIfNeeded];
    XCTAssertFalse(seeded2, @"Second seed should return NO (users already exist)");

    // Verify user count remains 3 — no duplicates created.
    __block NSArray *users = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [[CPCoreDataStack sharedStack] performBackgroundTask:^(NSManagedObjectContext *ctx) {
        NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"User"];
        users = [ctx executeFetchRequest:req error:nil] ?: @[];
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));

    XCTAssertEqual(users.count, (NSUInteger)3,
                   @"User count must remain 3 after double-seed — no duplicates");
}

// ---------------------------------------------------------------------------
// 13. testLogoutClearsSession
// ---------------------------------------------------------------------------
- (void)testLogoutClearsSession {
    [self createTestUserWithUsername:@"testuser_logout" role:@"Administrator"];

    XCTestExpectation *exp = [self expectationWithDescription:@"loginBeforeLogout"];
    [[CPAuthService sharedService] loginWithUsername:@"testuser_logout"
                                            password:kTestPassword
                                          completion:^(BOOL success, NSError *error) {
        XCTAssertTrue(success);
        [exp fulfill];
    }];
    [self waitForExpectationsWithTimeout:10 handler:nil];

    XCTAssertTrue([CPAuthService sharedService].isSessionValid,
                  @"Session should be valid before logout");

    [[CPAuthService sharedService] logout];

    XCTAssertFalse([CPAuthService sharedService].isSessionValid,
                   @"isSessionValid should be NO after logout");
    XCTAssertNil([CPAuthService sharedService].currentUserID,
                 @"currentUserID should be nil after logout");
    XCTAssertNil([CPAuthService sharedService].currentUsername,
                 @"currentUsername should be nil after logout");
}

// ===========================================================================
// F-06 security-bootstrap tests
// ===========================================================================

// ---------------------------------------------------------------------------
// 14. testSeededAccountsRequirePasswordChangeFlag
// Verifies that after first-run seeding, all three accounts are registered
// in the forced-rotation list.
// ---------------------------------------------------------------------------
- (void)testSeededAccountsRequirePasswordChangeFlag {
    BOOL seeded = [[CPAuthService sharedService] seedDefaultUsersIfNeeded];
    XCTAssertTrue(seeded, @"Seeding should succeed on a fresh store");

    NSArray *mustChange = [[NSUserDefaults standardUserDefaults]
                               arrayForKey:@"cp_must_change_password_uuids"];
    XCTAssertEqual(mustChange.count, (NSUInteger)3,
                   @"All three seeded accounts must be registered for forced rotation");

    // Each entry must be a non-empty UUID string.
    for (id entry in mustChange) {
        XCTAssertTrue([entry isKindOfClass:[NSString class]] && [entry length] > 0,
                      @"Each rotation-flag entry must be a non-empty UUID string");
    }
}

// ---------------------------------------------------------------------------
// 15. testSeededAccountsCannotUseFormerDefaultPasswords
// Proves the old static bootstrap passwords (Admin1234Pass etc.) no longer
// work for seeded accounts — a critical F-06 invariant.
// ---------------------------------------------------------------------------
- (void)testSeededAccountsCannotUseFormerDefaultPasswords {
    [[CPAuthService sharedService] seedDefaultUsersIfNeeded];

    // These were the hardcoded passwords previously embedded in source code.
    NSArray *formerCredentials = @[
        @[@"admin",      @"Admin1234Pass"],
        @[@"technician", @"Tech1234Pass"],
        @[@"finance",    @"Fin1234Pass"],
    ];

    for (NSArray *pair in formerCredentials) {
        XCTestExpectation *exp = [self expectationWithDescription:
                                  [NSString stringWithFormat:@"noStaticLogin_%@", pair[0]]];
        [[CPAuthService sharedService] loginWithUsername:pair[0]
                                                password:pair[1]
                                              completion:^(BOOL success, NSError *error) {
            XCTAssertFalse(success,
                @"Former static password must NOT work for seeded user '%@'. "
                @"Hardcoded credentials have been removed from the bootstrap path.", pair[0]);
            [exp fulfill];
        }];
        [self waitForExpectationsWithTimeout:10 handler:nil];
    }
}

// ---------------------------------------------------------------------------
// 16. testForcedPasswordChangeFlowClearsFlag
// End-to-end: create a user, add their UUID to the rotation list, log in,
// call forceChangePasswordForUserID:, verify needsPasswordChange is cleared
// and the UUID is removed from NSUserDefaults.
// ---------------------------------------------------------------------------
- (void)testForcedPasswordChangeFlowClearsFlag {
    [self createTestUserWithUsername:@"testuser_fpc" role:@"Administrator"];

    // Find the user's UUID.
    __block NSString *userUUID = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [[CPCoreDataStack sharedStack] performBackgroundTask:^(NSManagedObjectContext *ctx) {
        NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"User"];
        req.predicate  = [NSPredicate predicateWithFormat:@"username == %@", @"testuser_fpc"];
        req.fetchLimit = 1;
        NSArray *results = [ctx executeFetchRequest:req error:nil];
        userUUID = [results.firstObject valueForKey:@"uuid"];
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
    XCTAssertNotNil(userUUID, @"Test user UUID must be retrievable");

    // Manually register the UUID as requiring rotation (simulates seed behaviour).
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:@[userUUID] forKey:@"cp_must_change_password_uuids"];
    [defaults synchronize];

    // Log in — needsPasswordChange must be YES.
    XCTestExpectation *loginExp = [self expectationWithDescription:@"loginForFPC"];
    [[CPAuthService sharedService] loginWithUsername:@"testuser_fpc"
                                            password:kTestPassword
                                          completion:^(BOOL success, NSError *error) {
        XCTAssertTrue(success, @"Login should succeed");
        [loginExp fulfill];
    }];
    [self waitForExpectationsWithTimeout:10 handler:nil];

    XCTAssertTrue([CPAuthService sharedService].needsPasswordChange,
                  @"needsPasswordChange must be YES immediately after login for a rotation-flagged account");

    // Perform the forced password change.
    NSError *changeError = nil;
    BOOL changed = [[CPAuthService sharedService] forceChangePasswordForUserID:userUUID
                                                                   newPassword:@"NewSecure9876"
                                                                         error:&changeError];
    XCTAssertTrue(changed, @"forceChangePasswordForUserID: must succeed; error: %@", changeError);
    XCTAssertNil(changeError, @"No error expected on valid new password");

    // Rotation flag must now be cleared.
    XCTAssertFalse([CPAuthService sharedService].needsPasswordChange,
                   @"needsPasswordChange must be NO after successful forced change");

    NSArray *remaining = [[NSUserDefaults standardUserDefaults]
                              arrayForKey:@"cp_must_change_password_uuids"];
    XCTAssertFalse([remaining containsObject:userUUID],
                   @"UUID must be removed from cp_must_change_password_uuids after rotation");

    // New password must now work for login.
    [[CPAuthService sharedService] logout];
    XCTestExpectation *reloginExp = [self expectationWithDescription:@"loginNewPass"];
    [[CPAuthService sharedService] loginWithUsername:@"testuser_fpc"
                                            password:@"NewSecure9876"
                                          completion:^(BOOL success, NSError *error) {
        XCTAssertTrue(success, @"Login with new password must succeed after forced change");
        XCTAssertNil(error);
        [reloginExp fulfill];
    }];
    [self waitForExpectationsWithTimeout:10 handler:nil];

    [[CPAuthService sharedService] logout];
}

@end
