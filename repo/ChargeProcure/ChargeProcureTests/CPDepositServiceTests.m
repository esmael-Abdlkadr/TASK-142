#import <XCTest/XCTest.h>
#import "CPDepositService.h"
#import "CPAuthService.h"
#import "CPCoreDataStack.h"
#import "CPTestCoreDataStack.h"
#import <CoreData/CoreData.h>

/// Known password for all test-owned accounts in this suite.
static NSString * const kDepTestPass = @"Test1234Pass";

@interface CPDepositServiceTests : XCTestCase
@end

@implementation CPDepositServiceTests

- (void)setUp {
    [super setUp];
    [[CPTestCoreDataStack sharedStack] resetAll];

    // Wipe user store so seeding is fresh.
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

    [[CPAuthService sharedService] seedDefaultUsersWithPassword:kDepTestPass];
    [self loginAs:@"admin" password:kDepTestPass];
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
// 1. Create deposit – happy path
// ---------------------------------------------------------------------------
- (void)testCreateDepositSuccess {
    NSError *err = nil;
    NSDecimalNumber *dep   = [NSDecimalNumber decimalNumberWithString:@"50.00"];
    NSDecimalNumber *preA  = [NSDecimalNumber decimalNumberWithString:@"100.00"];
    NSString *uuid = [[CPDepositService sharedService]
                      createDepositForChargerID:@"CHG-001"
                                    customerRef:@"CUST-A"
                                  depositAmount:dep
                                  preAuthAmount:preA
                                          notes:nil
                                          error:&err];
    XCTAssertNotNil(uuid, @"UUID should be returned on success");
    XCTAssertNil(err, @"No error expected on success");

    NSManagedObject *fetched = [[CPDepositService sharedService] fetchDepositWithUUID:uuid];
    XCTAssertNotNil(fetched);
    XCTAssertEqualObjects([fetched valueForKey:@"status"], CPDepositStatusPending);
    XCTAssertEqualObjects([fetched valueForKey:@"chargerID"], @"CHG-001");
}

// ---------------------------------------------------------------------------
// 2. Create deposit – missing charger ID
// ---------------------------------------------------------------------------
- (void)testCreateDepositMissingChargerID {
    NSError *err = nil;
    NSString *uuid = [[CPDepositService sharedService]
                      createDepositForChargerID:@""
                                    customerRef:nil
                                  depositAmount:[NSDecimalNumber decimalNumberWithString:@"50"]
                                  preAuthAmount:[NSDecimalNumber decimalNumberWithString:@"100"]
                                          notes:nil
                                          error:&err];
    XCTAssertNil(uuid);
    XCTAssertEqual(err.code, CPDepositErrorInvalidAmount);
}

// ---------------------------------------------------------------------------
// 3. State machine: Pending → Captured
// ---------------------------------------------------------------------------
- (void)testCaptureDepositFromPending {
    NSString *uuid = [self _createDepositAndReturnUUID];
    XCTAssertNotNil(uuid);

    NSError *err = nil;
    BOOL ok = [[CPDepositService sharedService] captureDepositWithUUID:uuid error:&err];
    XCTAssertTrue(ok);
    XCTAssertNil(err);

    NSManagedObject *dep = [[CPDepositService sharedService] fetchDepositWithUUID:uuid];
    XCTAssertEqualObjects([dep valueForKey:@"status"], CPDepositStatusCaptured);
    XCTAssertNotNil([dep valueForKey:@"capturedAt"]);
}

// ---------------------------------------------------------------------------
// 4. State machine: Pending → Released
// ---------------------------------------------------------------------------
- (void)testReleaseDepositFromPending {
    NSString *uuid = [self _createDepositAndReturnUUID];
    NSError *err = nil;
    BOOL ok = [[CPDepositService sharedService] releaseDepositWithUUID:uuid error:&err];
    XCTAssertTrue(ok);
    NSManagedObject *dep = [[CPDepositService sharedService] fetchDepositWithUUID:uuid];
    XCTAssertEqualObjects([dep valueForKey:@"status"], CPDepositStatusReleased);
}

// ---------------------------------------------------------------------------
// 5. State machine: Pending → Failed
// ---------------------------------------------------------------------------
- (void)testMarkDepositFailed {
    NSString *uuid = [self _createDepositAndReturnUUID];
    NSError *err = nil;
    BOOL ok = [[CPDepositService sharedService] markDepositFailedWithUUID:uuid error:&err];
    XCTAssertTrue(ok);
    NSManagedObject *dep = [[CPDepositService sharedService] fetchDepositWithUUID:uuid];
    XCTAssertEqualObjects([dep valueForKey:@"status"], CPDepositStatusFailed);
}

// ---------------------------------------------------------------------------
// 6. State machine: Captured → Released
// ---------------------------------------------------------------------------
- (void)testReleaseDepositFromCaptured {
    NSString *uuid = [self _createDepositAndReturnUUID];
    [[CPDepositService sharedService] captureDepositWithUUID:uuid error:nil];

    NSError *err = nil;
    BOOL ok = [[CPDepositService sharedService] releaseDepositWithUUID:uuid error:&err];
    XCTAssertTrue(ok, @"Release from Captured should succeed");
    NSManagedObject *dep = [[CPDepositService sharedService] fetchDepositWithUUID:uuid];
    XCTAssertEqualObjects([dep valueForKey:@"status"], CPDepositStatusReleased);
}

// ---------------------------------------------------------------------------
// 7. State machine: invalid transition (Captured → Pending/Captured)
// ---------------------------------------------------------------------------
- (void)testCaptureAlreadyCapturedDepositFails {
    NSString *uuid = [self _createDepositAndReturnUUID];
    [[CPDepositService sharedService] captureDepositWithUUID:uuid error:nil];

    NSError *err = nil;
    BOOL ok = [[CPDepositService sharedService] captureDepositWithUUID:uuid error:&err];
    XCTAssertFalse(ok, @"Capturing an already-captured deposit should fail");
    XCTAssertEqual(err.code, CPDepositErrorInvalidState);
}

// ---------------------------------------------------------------------------
// 8. Unknown UUID returns not-found error
// ---------------------------------------------------------------------------
- (void)testCaptureNonExistentDepositFails {
    NSError *err = nil;
    BOOL ok = [[CPDepositService sharedService] captureDepositWithUUID:@"00000000-0000-0000-0000-000000000000" error:&err];
    XCTAssertFalse(ok);
    XCTAssertEqual(err.code, CPDepositErrorNotFound);
}

// ---------------------------------------------------------------------------
// 9. fetchDepositsForChargerID
// ---------------------------------------------------------------------------
- (void)testFetchDepositsForChargerID {
    [self _createDepositForCharger:@"CHG-A"];
    [self _createDepositForCharger:@"CHG-A"];
    [self _createDepositForCharger:@"CHG-B"];

    NSArray *forA = [[CPDepositService sharedService] fetchDepositsForChargerID:@"CHG-A"];
    NSArray *forB = [[CPDepositService sharedService] fetchDepositsForChargerID:@"CHG-B"];

    XCTAssertEqual(forA.count, 2u);
    XCTAssertEqual(forB.count, 1u);
}

// ---------------------------------------------------------------------------
// 10. Permission denied for non-finance / non-admin user
// ---------------------------------------------------------------------------
- (void)testCreateDepositDeniedForTechnician {
    [self loginAs:@"technician" password:kDepTestPass];
    NSError *err = nil;
    NSString *uuid = [[CPDepositService sharedService]
                      createDepositForChargerID:@"CHG-X"
                                    customerRef:nil
                                  depositAmount:[NSDecimalNumber decimalNumberWithString:@"10"]
                                  preAuthAmount:[NSDecimalNumber decimalNumberWithString:@"20"]
                                          notes:nil
                                          error:&err];
    XCTAssertNil(uuid, @"Technician should not be able to create deposits");
    XCTAssertEqual(err.code, CPDepositErrorPermission);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

- (NSString *)_createDepositAndReturnUUID {
    return [self _createDepositForCharger:@"CHG-TEST"];
}

- (NSString *)_createDepositForCharger:(NSString *)chargerID {
    return [[CPDepositService sharedService]
            createDepositForChargerID:chargerID
                           customerRef:nil
                         depositAmount:[NSDecimalNumber decimalNumberWithString:@"50"]
                         preAuthAmount:[NSDecimalNumber decimalNumberWithString:@"100"]
                                 notes:nil
                                 error:nil];
}

@end
