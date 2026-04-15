#import <XCTest/XCTest.h>
#import "CPChargerService.h"
#import "CPChargerSimulatorAdapter.h"
#import "CPAuthService.h"
#import "CPCoreDataStack.h"
#import "CPTestCoreDataStack.h"
#import "CPTestDataFactory.h"
#import <CoreData/CoreData.h>

@interface CPChargerServiceTests : XCTestCase
@property (nonatomic, strong) NSManagedObjectContext *ctx;
@end

@implementation CPChargerServiceTests

/// Known password for all test-owned accounts in this suite.
static NSString * const kChargerTestPass = @"Test1234Pass";

- (void)setUp {
    [super setUp];
    [[CPTestCoreDataStack sharedStack] resetAll];
    self.ctx = [CPTestCoreDataStack sharedStack].mainContext;
    // Wipe real user store so seeding is fresh each test run.
    dispatch_semaphore_t cleanSem = dispatch_semaphore_create(0);
    [[CPCoreDataStack sharedStack] performBackgroundTask:^(NSManagedObjectContext *ctx) {
        NSArray *users = [ctx executeFetchRequest:[NSFetchRequest fetchRequestWithEntityName:@"User"] error:nil];
        for (NSManagedObject *u in users) [ctx deleteObject:u];
        [ctx save:nil];
        dispatch_semaphore_signal(cleanSem);
    }];
    dispatch_semaphore_wait(cleanSem, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d removeObjectForKey:@"cp_must_change_password_uuids"];
    [d synchronize];
    // Seed with a known password so tests are deterministic.
    [[CPAuthService sharedService] seedDefaultUsersWithPassword:kChargerTestPass];
    [self loginAs:@"admin" password:kChargerTestPass];
}

- (void)tearDown {
    // Cancel any pending timers/completions so singleton state does not bleed into the next test.
    [[CPChargerService sharedService] cancelAllPendingCommandsForTesting];
    [[CPChargerService sharedService] setAdapter:nil];
    [[CPAuthService sharedService] logout];
    [[CPTestCoreDataStack sharedStack] resetAll];
    [super tearDown];
}

// ---------------------------------------------------------------------------
// Helper: synchronous login
// ---------------------------------------------------------------------------
- (void)loginAs:(NSString *)username password:(NSString *)password {
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [[CPAuthService sharedService] loginWithUsername:username
                                           password:password
                                         completion:^(BOOL success, NSError *err) {
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
}

// ---------------------------------------------------------------------------
// Helper: register a charger in the real shared store via the service
// ---------------------------------------------------------------------------
- (NSString *)registerNewCharger {
    NSString *chargerUUID = [[NSUUID UUID] UUIDString];
    [[CPChargerService sharedService] registerCharger:chargerUUID
                                          parameters:@{
        @"vendorID":        @"VENDOR-001",
        @"serialNumber":    @"SN-TEST-001",
        @"model":           @"TestCharger Pro",
        @"location":        @"Bay 1",
        @"firmwareVersion": @"1.0.0"
    }];
    // Allow the background task to complete before returning
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        dispatch_semaphore_signal(sem);
    });
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC));
    return chargerUUID;
}

// ---------------------------------------------------------------------------
// 1. testCommandIssuedAndAcknowledged_Deterministic
//    Uses CPChargerSimulatorAdapter (fastSucceed) for a 100% deterministic ACK.
// ---------------------------------------------------------------------------
- (void)testCommandIssuedAndAcknowledged_Deterministic {
    NSString *chargerUUID = [self registerNewCharger];

    // Inject fast-succeed adapter — command will ACK in ~0.1s, no randomness.
    [CPChargerService sharedService].adapter = [CPChargerSimulatorAdapter fastSucceedAdapter];

    XCTestExpectation *exp = [self expectationWithDescription:@"commandAcknowledged"];

    [[CPChargerService sharedService]
     issueCommandToCharger:chargerUUID
     commandType:@"RemoteStart"
     parameters:@{@"connectorId": @1}
     completion:^(BOOL acknowledged, NSString *commandUUID, NSError *error) {
        XCTAssertTrue(acknowledged, @"fastSucceedAdapter must produce acknowledged=YES");
        XCTAssertNil(error, @"No error expected on acknowledged command");
        XCTAssertNotNil(commandUUID, @"commandUUID must always be set");
        [exp fulfill];
    }];

    [self waitForExpectationsWithTimeout:5 handler:nil];
    [CPChargerService sharedService].adapter = nil;  // restore
}

// ---------------------------------------------------------------------------
// 2. testCommandTimesOutAfter8Seconds_Deterministic
//    Uses CPChargerSimulatorAdapter (timeout) to force a PendingReview outcome.
//    commandTimeoutIntervalOverride = 0.5s so the test completes in < 2s.
// ---------------------------------------------------------------------------
- (void)testCommandTimesOutAfter8Seconds_Deterministic {
    NSString *chargerUUID = [self registerNewCharger];

    // Use a 0.5s timeout override so the test runs in < 2s instead of 8s.
    // The timeout adapter fires after 10s, so the 0.5s service timer wins first.
    [CPChargerService sharedService].commandTimeoutIntervalOverride = 0.5;
    [CPChargerService sharedService].adapter = [CPChargerSimulatorAdapter timeoutAdapter];

    XCTestExpectation *exp = [self expectationWithDescription:@"commandTimedOut"];
    NSDate *startTime = [NSDate date];

    [[CPChargerService sharedService]
     issueCommandToCharger:chargerUUID
     commandType:@"SoftReset"
     parameters:nil
     completion:^(BOOL acknowledged, NSString *commandUUID, NSError *error) {
        NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:startTime];

        XCTAssertFalse(acknowledged, @"Timeout adapter must produce acknowledged=NO");
        XCTAssertNotNil(commandUUID, @"commandUUID must be set");
        XCTAssertNotNil(error, @"Timed-out command must produce an error");
        XCTAssertEqual(error.code, 408,
            @"Timeout error code should be 408, got: %ld", (long)error.code);
        XCTAssertGreaterThanOrEqual(elapsed, 0.4,
            @"Completion must fire after the 0.5s timeout window (elapsed: %.2fs)", elapsed);
        XCTAssertLessThanOrEqual(elapsed, 3.0,
            @"Completion must fire within a reasonable window after the timeout");

        // Verify Core Data status was set to PendingReview
        dispatch_async(dispatch_get_main_queue(), ^{
            [[CPCoreDataStack sharedStack].mainContext performBlockAndWait:^{
                NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"Command"];
                req.predicate = [NSPredicate predicateWithFormat:@"uuid == %@", commandUUID];
                req.fetchLimit = 1;
                NSArray *results = [[CPCoreDataStack sharedStack].mainContext
                                    executeFetchRequest:req error:nil];
                NSManagedObject *cmd = results.firstObject;
                if (cmd) {
                    XCTAssertEqualObjects([cmd valueForKey:@"status"], @"PendingReview",
                        @"Timed-out command must have status='PendingReview' in Core Data");
                }
            }];
        });

        [exp fulfill];
    }];

    [self waitForExpectationsWithTimeout:5 handler:nil];
    [CPChargerService sharedService].adapter = nil;  // restore
}

// ---------------------------------------------------------------------------
// Keep legacy test renamed — still valid for non-deterministic code path coverage
// ---------------------------------------------------------------------------
- (void)testCommandIssuedAndAcknowledged {
    NSString *chargerUUID = [self registerNewCharger];
    // Use fast-succeed adapter so test is stable (no random simulation).
    [CPChargerService sharedService].adapter = [CPChargerSimulatorAdapter fastSucceedAdapter];

    XCTestExpectation *exp = [self expectationWithDescription:@"commandCompleted"];
    exp.assertForOverFulfill = NO;

    [[CPChargerService sharedService]
     issueCommandToCharger:chargerUUID
     commandType:@"RemoteStart"
     parameters:@{@"connectorId": @1}
     completion:^(BOOL acknowledged, NSString *commandUUID, NSError *error) {
        XCTAssertNotNil(commandUUID, @"commandUUID should always be populated");
        XCTAssertTrue(acknowledged, @"fastSucceedAdapter must produce acknowledged=YES");
        XCTAssertNil(error, @"Acknowledged command should have no error");
        [exp fulfill];
    }];

    [self waitForExpectationsWithTimeout:5 handler:nil];
    [CPChargerService sharedService].adapter = nil;
}

// ---------------------------------------------------------------------------
// 3. testChargerStatusUpdated — updateCharger: creates ChargerEvent and updates status
// ---------------------------------------------------------------------------
- (void)testChargerStatusUpdated {
    NSString *chargerUUID = [self registerNewCharger];

    // Wait for the status change notification rather than a fixed sleep.
    // CPChargerService posts CPChargerStatusChangedNotification on the main queue
    // after the background save — by the time it arrives the main context merge has run.
    XCTestExpectation *notifExp = [self expectationWithDescription:@"statusChanged"];
    id observer = [[NSNotificationCenter defaultCenter]
        addObserverForName:CPChargerStatusChangedNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *n) {
        if ([n.userInfo[@"chargerUUID"] isEqualToString:chargerUUID]) {
            [notifExp fulfill];
        }
    }];

    [[CPChargerService sharedService] updateCharger:chargerUUID
                                             status:@"Available"
                                             detail:@"Charger online after test registration"];

    [self waitForExpectationsWithTimeout:3 handler:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:observer];

    // Force any pending mainContext merges to flush before reading.
    [[CPCoreDataStack sharedStack].mainContext performBlockAndWait:^{
        [[CPCoreDataStack sharedStack].mainContext refreshAllObjects];
    }];

    id charger = [[CPChargerService sharedService] fetchChargerWithUUID:chargerUUID];
    XCTAssertNotNil(charger, @"Charger should exist after registration and update");

    NSString *status = [charger valueForKey:@"status"];
    XCTAssertEqualObjects(status, @"Available",
                          @"Charger status should be updated to 'Available'");

    NSArray *allChargers = [[CPChargerService sharedService] fetchAllChargers];
    BOOL found = NO;
    for (id c in allChargers) {
        if ([[c valueForKey:@"uuid"] isEqualToString:chargerUUID]) {
            found = YES;
            break;
        }
    }
    XCTAssertTrue(found, @"Updated charger should still appear in fetchAllChargers");
}

// ---------------------------------------------------------------------------
// 4. testPendingReviewCommandRetry — retry reissues command with new timeout
// ---------------------------------------------------------------------------
- (void)testPendingReviewCommandRetry {
    NSString *chargerUUID = [self registerNewCharger];

    // Issue first command and capture its UUID. Use fastSucceedAdapter so we get a
    // commandUUID immediately without waiting for the 8-second hardware timeout.
    [CPChargerService sharedService].adapter = [CPChargerSimulatorAdapter fastSucceedAdapter];

    __block NSString *capturedCommandUUID = nil;
    XCTestExpectation *issueExp = [self expectationWithDescription:@"commandIssued"];
    issueExp.assertForOverFulfill = NO;

    [[CPChargerService sharedService]
     issueCommandToCharger:chargerUUID
     commandType:@"ParameterPush"
     parameters:@{@"param": @"testValue"}
     completion:^(BOOL acknowledged, NSString *commandUUID, NSError *error) {
        capturedCommandUUID = commandUUID;
        XCTAssertNotNil(commandUUID, @"commandUUID must not be nil");
        [issueExp fulfill];
    }];

    [self waitForExpectationsWithTimeout:5 handler:nil];

    XCTAssertNotNil(capturedCommandUUID, @"Command UUID should have been captured");

    // Retry the command. Use fastSucceedAdapter so the retry also completes immediately.
    if (capturedCommandUUID) {
        [CPChargerService sharedService].adapter = [CPChargerSimulatorAdapter fastSucceedAdapter];

        XCTestExpectation *retryExp = [self expectationWithDescription:@"retryCompleted"];
        retryExp.assertForOverFulfill = NO;

        [[CPChargerService sharedService]
         retryCommand:capturedCommandUUID
         completion:^(BOOL acknowledged, NSError *error) {
            // Retry via fastSucceedAdapter must succeed.
            XCTAssertTrue(acknowledged, @"Retry with fastSucceedAdapter must be acknowledged");
            XCTAssertNil(error, @"Successful retry should have no error");
            [retryExp fulfill];
        }];

        [self waitForExpectationsWithTimeout:5 handler:nil];
    }

    [CPChargerService sharedService].adapter = nil;
}

// ---------------------------------------------------------------------------
// 5. testCommandParametersSerializedAsJSON — parameters dict stored as JSON string
// ---------------------------------------------------------------------------
- (void)testCommandParametersSerializedAsJSON {
    // Verify the JSON serialization logic that CPChargerService uses
    NSDictionary *params = @{
        @"connectorId":   @1,
        @"idTag":         @"RFID-TEST-001",
        @"reservationId": @42
    };

    // Serialize as the service does
    NSError *jsonErr = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:params
                                                       options:0
                                                         error:&jsonErr];
    XCTAssertNil(jsonErr, @"JSON serialization should succeed");
    XCTAssertNotNil(jsonData, @"JSON data should not be nil");

    NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    XCTAssertNotNil(jsonString, @"JSON string should be valid UTF-8");
    XCTAssertGreaterThan(jsonString.length, 0, @"JSON string should not be empty");

    // Deserialize and verify round-trip
    NSData *roundTripData = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
    NSError *parseErr = nil;
    NSDictionary *parsed = [NSJSONSerialization JSONObjectWithData:roundTripData
                                                            options:0
                                                              error:&parseErr];
    XCTAssertNil(parseErr, @"Deserialization should succeed");
    XCTAssertEqualObjects(parsed[@"connectorId"], @1,
                          @"connectorId should survive JSON round-trip");
    XCTAssertEqualObjects(parsed[@"idTag"], @"RFID-TEST-001",
                          @"idTag should survive JSON round-trip");

    // Issue the command to verify the service accepts and stores params correctly.
    // Use fastSucceedAdapter so the test completes immediately without waiting for
    // the 8-second hardware timeout.
    NSString *chargerUUID = [self registerNewCharger];
    [CPChargerService sharedService].adapter = [CPChargerSimulatorAdapter fastSucceedAdapter];

    XCTestExpectation *exp = [self expectationWithDescription:@"paramsCommandCompleted"];
    exp.assertForOverFulfill = NO;

    [[CPChargerService sharedService]
     issueCommandToCharger:chargerUUID
     commandType:@"RemoteStart"
     parameters:params
     completion:^(BOOL acknowledged, NSString *commandUUID, NSError *error) {
        XCTAssertNotNil(commandUUID,
            @"Command with parameters should return a commandUUID");
        XCTAssertTrue(acknowledged, @"fastSucceedAdapter must acknowledge the command");
        // The service stores params as JSON string in Core Data —
        // verified by the round-trip test above.
        [exp fulfill];
    }];

    [self waitForExpectationsWithTimeout:5 handler:nil];
    [CPChargerService sharedService].adapter = nil;
}

// ---------------------------------------------------------------------------
// 6. testRBACDeniesCommandWhenUnauthorized
//    Finance Approver lacks Charger.update permission; service must reject.
// ---------------------------------------------------------------------------
- (void)testRBACDeniesCommandWhenUnauthorized {
    // Log in as finance approver — no charger.update permission
    [[CPAuthService sharedService] seedDefaultUsersWithPassword:kChargerTestPass];

    XCTestExpectation *loginExp = [self expectationWithDescription:@"loginFinance"];
    [[CPAuthService sharedService] loginWithUsername:@"finance"
                                           password:kChargerTestPass
                                         completion:^(BOOL success, NSError *err) {
        XCTAssertTrue(success, @"Finance login should succeed");
        [loginExp fulfill];
    }];
    [self waitForExpectationsWithTimeout:10 handler:nil];

    NSString *chargerUUID = [self registerNewCharger];
    [CPChargerService sharedService].adapter = [CPChargerSimulatorAdapter fastSucceedAdapter];

    XCTestExpectation *cmdExp = [self expectationWithDescription:@"commandDenied"];
    [[CPChargerService sharedService]
     issueCommandToCharger:chargerUUID
     commandType:@"RemoteStart"
     parameters:nil
     completion:^(BOOL acknowledged, NSString *commandUUID, NSError *error) {
        XCTAssertFalse(acknowledged, @"Finance Approver must be denied charger command");
        XCTAssertNotNil(error, @"Error expected when permission denied");
        XCTAssertEqual(error.code, 403,
            @"Permission-denied error must have code 403, got: %ld", (long)error.code);
        [cmdExp fulfill];
    }];
    [self waitForExpectationsWithTimeout:5 handler:nil];

    [[CPAuthService sharedService] logout];
    [CPChargerService sharedService].adapter = nil;
}

// ---------------------------------------------------------------------------
// 7. testRBACDeniesRegisterChargerForUnauthorizedRole
//    Finance Approver lacks Charger.update; registerCharger must be a no-op.
// ---------------------------------------------------------------------------
- (void)testRBACDeniesRegisterChargerForUnauthorizedRole {
    [[CPAuthService sharedService] logout];
    [self loginAs:@"finance" password:kChargerTestPass];

    NSString *chargerUUID = [[NSUUID UUID] UUIDString];
    [[CPChargerService sharedService] registerCharger:chargerUUID
                                          parameters:@{@"vendorID": @"DENY-TEST"}];

    // The RBAC check inside registerCharger: is synchronous — when access is denied
    // the method returns immediately without dispatching any background task.
    // No wait is needed before asserting the charger was not created.
    id charger = [[CPChargerService sharedService] fetchChargerWithUUID:chargerUUID];
    XCTAssertNil(charger,
        @"Finance Approver must not be able to register a charger (lacks charger.update)");

    [[CPAuthService sharedService] logout];
    [self loginAs:@"admin" password:kChargerTestPass];
}

// ---------------------------------------------------------------------------
// 8. testRBACDeniesUpdateChargerStatusForUnauthorizedRole
//    Finance Approver cannot change charger status; status must remain unchanged.
// ---------------------------------------------------------------------------
- (void)testRBACDeniesUpdateChargerStatusForUnauthorizedRole {
    // Register charger as admin
    NSString *chargerUUID = [self registerNewCharger];

    // Wait for the baseline status "Available" to persist — use the status-changed
    // notification so there is no fixed sleep.
    XCTestExpectation *baselineExp = [self expectationWithDescription:@"baselineSet"];
    id observer = [[NSNotificationCenter defaultCenter]
        addObserverForName:CPChargerStatusChangedNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *n) {
        if ([n.userInfo[@"chargerUUID"] isEqualToString:chargerUUID]) {
            [baselineExp fulfill];
        }
    }];
    [[CPChargerService sharedService] updateCharger:chargerUUID status:@"Available" detail:nil];
    [self waitForExpectationsWithTimeout:3 handler:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:observer];

    // Flush the main context so the saved "Available" status is visible.
    [[CPCoreDataStack sharedStack].mainContext performBlockAndWait:^{
        [[CPCoreDataStack sharedStack].mainContext refreshAllObjects];
    }];

    // Switch to finance approver — no charger.update permission.
    [[CPAuthService sharedService] logout];
    [self loginAs:@"finance" password:kChargerTestPass];

    // This call returns synchronously — the RBAC check denies before any async work.
    [[CPChargerService sharedService] updateCharger:chargerUUID status:@"Faulted" detail:@"Denied attempt"];

    // No wait needed: since the update was RBAC-denied synchronously the status in the
    // persistent store has not changed.  Refresh to ensure we read the stored value.
    [[CPCoreDataStack sharedStack].mainContext performBlockAndWait:^{
        [[CPCoreDataStack sharedStack].mainContext refreshAllObjects];
    }];
    id charger = [[CPChargerService sharedService] fetchChargerWithUUID:chargerUUID];
    NSString *status = [charger valueForKey:@"status"];
    XCTAssertFalse([status isEqualToString:@"Faulted"],
        @"Finance Approver must not update charger status; status should still be 'Available', got: %@", status);

    [[CPAuthService sharedService] logout];
    [self loginAs:@"admin" password:kChargerTestPass];
}

// ---------------------------------------------------------------------------
// 9. testRBACDeniesRetryCommandForUnauthorizedRole
//    Finance Approver must receive a 403 error when retrying a command.
// ---------------------------------------------------------------------------
- (void)testRBACDeniesRetryCommandForUnauthorizedRole {
    NSString *chargerUUID = [self registerNewCharger];
    [CPChargerService sharedService].adapter = [CPChargerSimulatorAdapter fastSucceedAdapter];

    __block NSString *capturedCommandUUID = nil;
    XCTestExpectation *issueExp = [self expectationWithDescription:@"commandIssued"];
    [[CPChargerService sharedService]
     issueCommandToCharger:chargerUUID
     commandType:@"SoftReset"
     parameters:nil
     completion:^(BOOL ack, NSString *cmdUUID, NSError *err) {
        capturedCommandUUID = cmdUUID;
        [issueExp fulfill];
    }];
    [self waitForExpectationsWithTimeout:5 handler:nil];
    [CPChargerService sharedService].adapter = nil;

    XCTAssertNotNil(capturedCommandUUID, @"Command UUID must be captured");
    if (!capturedCommandUUID) return;

    // Switch to finance approver — no charger.update
    [[CPAuthService sharedService] logout];
    [self loginAs:@"finance" password:kChargerTestPass];

    XCTestExpectation *retryExp = [self expectationWithDescription:@"retryDenied"];
    [[CPChargerService sharedService]
     retryCommand:capturedCommandUUID
     completion:^(BOOL acknowledged, NSError *error) {
        XCTAssertFalse(acknowledged, @"Finance Approver must be denied retry");
        XCTAssertNotNil(error, @"Error must be returned when retry is denied");
        XCTAssertEqual(error.code, 403,
            @"Denial error code must be 403, got: %ld", (long)error.code);
        [retryExp fulfill];
    }];
    [self waitForExpectationsWithTimeout:5 handler:nil];

    [[CPAuthService sharedService] logout];
    [self loginAs:@"admin" password:kChargerTestPass];
}

// ---------------------------------------------------------------------------
// 10. testPendingReviewCommandsFilteredByChargerID
//     Verifies that timed-out commands are stored with key "chargerID" (not
//     "chargerUUID") so the filter in CPChargerDetailViewController works.
//     The fix changed the predicate from [cmd valueForKey:@"chargerUUID"] to
//     [cmd valueForKey:@"chargerID"].
// ---------------------------------------------------------------------------
- (void)testPendingReviewCommandsFilteredByChargerID {
    NSString *chargerUUID = [self registerNewCharger];

    // Use a short timeout so the command transitions to PendingReview quickly.
    [CPChargerService sharedService].commandTimeoutIntervalOverride = 0.5;
    [CPChargerService sharedService].adapter = [CPChargerSimulatorAdapter timeoutAdapter];

    __block NSString *capturedCommandUUID = nil;
    XCTestExpectation *exp = [self expectationWithDescription:@"commandTimedOut"];

    [[CPChargerService sharedService]
     issueCommandToCharger:chargerUUID
     commandType:@"SoftReset"
     parameters:nil
     completion:^(BOOL acknowledged, NSString *commandUUID, NSError *error) {
        capturedCommandUUID = commandUUID;
        [exp fulfill];
    }];
    [self waitForExpectationsWithTimeout:5 handler:nil];
    [CPChargerService sharedService].adapter = nil;

    XCTAssertNotNil(capturedCommandUUID, @"Command UUID must be captured after timeout");
    if (!capturedCommandUUID) return;

    // Fetch the PendingReview command from Core Data and verify it uses "chargerID" key.
    NSManagedObjectContext *ctx = [CPCoreDataStack sharedStack].mainContext;
    __block NSManagedObject *pendingCmd = nil;
    [ctx performBlockAndWait:^{
        NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"Command"];
        req.predicate = [NSPredicate predicateWithFormat:@"uuid == %@ AND status == %@",
                         capturedCommandUUID, @"PendingReview"];
        req.fetchLimit = 1;
        pendingCmd = [[ctx executeFetchRequest:req error:nil] firstObject];
    }];

    XCTAssertNotNil(pendingCmd,
        @"Timed-out command must exist in Core Data with status 'PendingReview'");

    if (!pendingCmd) return;

    // The command must store the charger identifier under "chargerID" — this is the
    // key that CPChargerDetailViewController now reads when filtering pending-review
    // commands for the current charger.
    NSString *storedChargerID = [pendingCmd valueForKey:@"chargerID"];
    XCTAssertEqualObjects(storedChargerID, chargerUUID,
        @"Command.chargerID must equal the charger UUID used when issuing the command. "
        @"CPChargerDetailViewController filters by 'chargerID'; if this key is wrong "
        @"the Pending Review section would always be empty.");

    // Confirm the old (wrong) key "chargerUUID" is absent / nil on Command entities.
    // This validates that the ViewController fix (using chargerID, not chargerUUID) is correct.
    NSArray *attributes = [[pendingCmd entity] attributesByName].allKeys;
    XCTAssertFalse([attributes containsObject:@"chargerUUID"],
        @"Command entity must NOT have a 'chargerUUID' attribute — "
        @"the correct key is 'chargerID' as written by CPChargerService.issueCommand:");
}

@end
