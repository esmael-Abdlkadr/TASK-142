#import <XCTest/XCTest.h>
#import "CPCouponService.h"
#import "CPAuthService.h"
#import "CPCoreDataStack.h"
#import "CPTestCoreDataStack.h"
#import <CoreData/CoreData.h>

/// Known password for all test-owned accounts in this suite.
static NSString * const kCouponTestPass = @"Test1234Pass";

@interface CPCouponServiceTests : XCTestCase
@end

@implementation CPCouponServiceTests

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
        // Clear any existing coupons
        for (NSManagedObject *c in [ctx executeFetchRequest:[NSFetchRequest fetchRequestWithEntityName:@"CouponPackage"] error:nil])
            [ctx deleteObject:c];
        [ctx save:nil];
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"cp_must_change_password_uuids"];
    [[NSUserDefaults standardUserDefaults] synchronize];

    [[CPAuthService sharedService] seedDefaultUsersWithPassword:kCouponTestPass];
    [self loginAs:@"admin" password:kCouponTestPass];
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
// 1. Create coupon – percentage type
// ---------------------------------------------------------------------------
- (void)testCreatePercentageCouponSuccess {
    NSError *err = nil;
    NSString *uuid = [[CPCouponService sharedService]
                      createCouponWithCode:@"SUMMER20"
                               description:@"Summer 20% off"
                              discountType:CPCouponDiscountTypePercentage
                             discountValue:[NSDecimalNumber decimalNumberWithString:@"20"]
                                 minAmount:nil
                               maxDiscount:nil
                                  maxUsage:nil
                            effectiveStart:nil
                              effectiveEnd:nil
                                     error:&err];
    XCTAssertNotNil(uuid, @"UUID should be returned for valid coupon creation");
    XCTAssertNil(err);

    NSManagedObject *fetched = [[CPCouponService sharedService] fetchCouponWithCode:@"SUMMER20"];
    XCTAssertNotNil(fetched);
    XCTAssertEqualObjects([fetched valueForKey:@"code"], @"SUMMER20");
    XCTAssertTrue([[fetched valueForKey:@"isActive"] boolValue]);
    XCTAssertEqualObjects([fetched valueForKey:@"usageCount"], @(0));
}

// ---------------------------------------------------------------------------
// 2. Create coupon – fixed type
// ---------------------------------------------------------------------------
- (void)testCreateFixedCouponSuccess {
    NSError *err = nil;
    NSString *uuid = [[CPCouponService sharedService]
                      createCouponWithCode:@"FLAT10"
                               description:nil
                              discountType:CPCouponDiscountTypeFixed
                             discountValue:[NSDecimalNumber decimalNumberWithString:@"10"]
                                 minAmount:[NSDecimalNumber decimalNumberWithString:@"50"]
                               maxDiscount:nil
                                  maxUsage:@(100)
                            effectiveStart:nil
                              effectiveEnd:nil
                                     error:&err];
    XCTAssertNotNil(uuid);
    XCTAssertNil(err);
}

// ---------------------------------------------------------------------------
// 3. Duplicate code rejected
// ---------------------------------------------------------------------------
- (void)testDuplicateCodeRejected {
    [self _createCouponWithCode:@"DUPE99" type:CPCouponDiscountTypePercentage value:@"10"];
    NSError *err = nil;
    NSString *uuid = [self _createCouponWithCode:@"DUPE99" type:CPCouponDiscountTypePercentage value:@"10"];
    XCTAssertNil(uuid, @"Duplicate code should be rejected");
    // err is not checked here since helper discards it; re-call to verify error code
    NSError *err2 = nil;
    NSString *uuid2 = [[CPCouponService sharedService]
                       createCouponWithCode:@"dupe99"   // case-insensitive duplicate
                                description:nil
                               discountType:CPCouponDiscountTypePercentage
                              discountValue:[NSDecimalNumber decimalNumberWithString:@"10"]
                                  minAmount:nil
                                maxDiscount:nil
                                   maxUsage:nil
                             effectiveStart:nil
                               effectiveEnd:nil
                                      error:&err2];
    XCTAssertNil(uuid2);
    XCTAssertEqual(err2.code, CPCouponErrorDuplicateCode);
}

// ---------------------------------------------------------------------------
// 4. Invalid discount type rejected
// ---------------------------------------------------------------------------
- (void)testInvalidDiscountTypeRejected {
    NSError *err = nil;
    NSString *uuid = [[CPCouponService sharedService]
                      createCouponWithCode:@"BAD1"
                               description:nil
                              discountType:@"bogus"
                             discountValue:[NSDecimalNumber decimalNumberWithString:@"5"]
                                 minAmount:nil
                               maxDiscount:nil
                                  maxUsage:nil
                            effectiveStart:nil
                              effectiveEnd:nil
                                     error:&err];
    XCTAssertNil(uuid);
    XCTAssertEqual(err.code, CPCouponErrorInvalidValue);
}

// ---------------------------------------------------------------------------
// 5. Zero discount value rejected
// ---------------------------------------------------------------------------
- (void)testZeroDiscountValueRejected {
    NSError *err = nil;
    NSString *uuid = [[CPCouponService sharedService]
                      createCouponWithCode:@"ZERO"
                               description:nil
                              discountType:CPCouponDiscountTypeFixed
                             discountValue:[NSDecimalNumber zero]
                                 minAmount:nil
                               maxDiscount:nil
                                  maxUsage:nil
                            effectiveStart:nil
                              effectiveEnd:nil
                                     error:&err];
    XCTAssertNil(uuid);
    XCTAssertEqual(err.code, CPCouponErrorInvalidValue);
}

// ---------------------------------------------------------------------------
// 6. Apply coupon – percentage discount
// ---------------------------------------------------------------------------
- (void)testApplyPercentageCoupon {
    [self _createCouponWithCode:@"PCT20" type:CPCouponDiscountTypePercentage value:@"20"];

    NSDecimalNumber *discount = nil;
    NSError *err = nil;
    NSDecimalNumber *purchase = [NSDecimalNumber decimalNumberWithString:@"100.00"];
    BOOL ok = [[CPCouponService sharedService] applyCouponWithCode:@"PCT20"
                                                   purchaseAmount:purchase
                                                    discountedOut:&discount
                                                            error:&err];
    XCTAssertTrue(ok);
    XCTAssertNil(err);
    // 20% of $100 = $20
    XCTAssertEqualWithAccuracy(discount.doubleValue, 20.0, 0.001);

    // Usage count should increment to 1
    NSManagedObject *c = [[CPCouponService sharedService] fetchCouponWithCode:@"PCT20"];
    XCTAssertEqualObjects([c valueForKey:@"usageCount"], @(1));
}

// ---------------------------------------------------------------------------
// 7. Apply coupon – fixed discount
// ---------------------------------------------------------------------------
- (void)testApplyFixedCoupon {
    [self _createCouponWithCode:@"FIXED15" type:CPCouponDiscountTypeFixed value:@"15"];

    NSDecimalNumber *discount = nil;
    NSError *err = nil;
    BOOL ok = [[CPCouponService sharedService] applyCouponWithCode:@"FIXED15"
                                                   purchaseAmount:[NSDecimalNumber decimalNumberWithString:@"200"]
                                                    discountedOut:&discount
                                                            error:&err];
    XCTAssertTrue(ok);
    XCTAssertEqualWithAccuracy(discount.doubleValue, 15.0, 0.001);
}

// ---------------------------------------------------------------------------
// 8. Apply coupon – maxDiscount cap respected
// ---------------------------------------------------------------------------
- (void)testApplyCouponRespectsMaxDiscountCap {
    NSError *err = nil;
    [[CPCouponService sharedService] createCouponWithCode:@"CAPTEST"
                                              description:nil
                                             discountType:CPCouponDiscountTypePercentage
                                            discountValue:[NSDecimalNumber decimalNumberWithString:@"50"]
                                                minAmount:nil
                                              maxDiscount:[NSDecimalNumber decimalNumberWithString:@"30"]
                                                 maxUsage:nil
                                           effectiveStart:nil
                                             effectiveEnd:nil
                                                    error:nil];
    NSDecimalNumber *discount = nil;
    BOOL ok = [[CPCouponService sharedService] applyCouponWithCode:@"CAPTEST"
                                                   purchaseAmount:[NSDecimalNumber decimalNumberWithString:@"200"]
                                                    discountedOut:&discount
                                                            error:&err];
    XCTAssertTrue(ok);
    // 50% of $200 = $100, but capped at $30
    XCTAssertEqualWithAccuracy(discount.doubleValue, 30.0, 0.001);
}

// ---------------------------------------------------------------------------
// 9. Apply coupon – minimum amount not met
// ---------------------------------------------------------------------------
- (void)testApplyCouponMinAmountNotMet {
    [[CPCouponService sharedService] createCouponWithCode:@"MINTEST"
                                              description:nil
                                             discountType:CPCouponDiscountTypeFixed
                                            discountValue:[NSDecimalNumber decimalNumberWithString:@"10"]
                                                minAmount:[NSDecimalNumber decimalNumberWithString:@"100"]
                                              maxDiscount:nil
                                                 maxUsage:nil
                                           effectiveStart:nil
                                             effectiveEnd:nil
                                                    error:nil];
    NSDecimalNumber *discount = nil;
    NSError *err = nil;
    BOOL ok = [[CPCouponService sharedService] applyCouponWithCode:@"MINTEST"
                                                   purchaseAmount:[NSDecimalNumber decimalNumberWithString:@"50"]
                                                    discountedOut:&discount
                                                            error:&err];
    XCTAssertFalse(ok);
    XCTAssertEqual(err.code, CPCouponErrorInvalidValue);
}

// ---------------------------------------------------------------------------
// 10. Apply coupon – maxUsage enforced
// ---------------------------------------------------------------------------
- (void)testApplyCouponMaxUsageEnforced {
    [[CPCouponService sharedService] createCouponWithCode:@"MAXUSE2"
                                              description:nil
                                             discountType:CPCouponDiscountTypeFixed
                                            discountValue:[NSDecimalNumber decimalNumberWithString:@"5"]
                                                minAmount:nil
                                              maxDiscount:nil
                                                 maxUsage:@(2)
                                           effectiveStart:nil
                                             effectiveEnd:nil
                                                    error:nil];
    NSDecimalNumber *purchase = [NSDecimalNumber decimalNumberWithString:@"100"];
    BOOL ok1 = [[CPCouponService sharedService] applyCouponWithCode:@"MAXUSE2"
                                                    purchaseAmount:purchase discountedOut:nil error:nil];
    BOOL ok2 = [[CPCouponService sharedService] applyCouponWithCode:@"MAXUSE2"
                                                    purchaseAmount:purchase discountedOut:nil error:nil];
    NSError *err = nil;
    BOOL ok3 = [[CPCouponService sharedService] applyCouponWithCode:@"MAXUSE2"
                                                    purchaseAmount:purchase discountedOut:nil error:&err];
    XCTAssertTrue(ok1);
    XCTAssertTrue(ok2);
    XCTAssertFalse(ok3, @"Third use should fail — maxUsage is 2");
    XCTAssertEqual(err.code, CPCouponErrorMaxUsageReached);
}

// ---------------------------------------------------------------------------
// 11. Apply coupon – expired (past effectiveEnd) rejected
// ---------------------------------------------------------------------------
- (void)testApplyExpiredCouponRejected {
    NSDate *yesterday = [NSDate dateWithTimeIntervalSinceNow:-86400];
    NSDate *twoDaysAgo = [NSDate dateWithTimeIntervalSinceNow:-172800];

    [[CPCouponService sharedService] createCouponWithCode:@"EXPIRED1"
                                              description:nil
                                             discountType:CPCouponDiscountTypeFixed
                                            discountValue:[NSDecimalNumber decimalNumberWithString:@"5"]
                                                minAmount:nil
                                              maxDiscount:nil
                                                 maxUsage:nil
                                           effectiveStart:twoDaysAgo
                                             effectiveEnd:yesterday
                                                    error:nil];
    NSError *err = nil;
    BOOL ok = [[CPCouponService sharedService] applyCouponWithCode:@"EXPIRED1"
                                                   purchaseAmount:[NSDecimalNumber decimalNumberWithString:@"50"]
                                                    discountedOut:nil
                                                            error:&err];
    XCTAssertFalse(ok);
    XCTAssertEqual(err.code, CPCouponErrorExpired);
}

// ---------------------------------------------------------------------------
// 12. Apply coupon – not-yet-valid (future effectiveStart) rejected
// ---------------------------------------------------------------------------
- (void)testApplyFutureCouponRejected {
    NSDate *tomorrow = [NSDate dateWithTimeIntervalSinceNow:86400];

    [[CPCouponService sharedService] createCouponWithCode:@"FUTURE1"
                                              description:nil
                                             discountType:CPCouponDiscountTypeFixed
                                            discountValue:[NSDecimalNumber decimalNumberWithString:@"5"]
                                                minAmount:nil
                                              maxDiscount:nil
                                                 maxUsage:nil
                                           effectiveStart:tomorrow
                                             effectiveEnd:nil
                                                    error:nil];
    NSError *err = nil;
    BOOL ok = [[CPCouponService sharedService] applyCouponWithCode:@"FUTURE1"
                                                   purchaseAmount:[NSDecimalNumber decimalNumberWithString:@"50"]
                                                    discountedOut:nil
                                                            error:&err];
    XCTAssertFalse(ok);
    XCTAssertEqual(err.code, CPCouponErrorExpired);
}

// ---------------------------------------------------------------------------
// 13. Deactivate and re-activate coupon
// ---------------------------------------------------------------------------
- (void)testDeactivateAndReactivateCoupon {
    NSString *uuid = [self _createCouponWithCode:@"TOGGLE1"
                                            type:CPCouponDiscountTypeFixed
                                           value:@"5"];
    XCTAssertNotNil(uuid);

    NSError *err = nil;
    BOOL deactivated = [[CPCouponService sharedService] deactivateCouponWithUUID:uuid error:&err];
    XCTAssertTrue(deactivated);

    // Apply should fail after deactivation
    NSError *applyErr = nil;
    BOOL ok = [[CPCouponService sharedService] applyCouponWithCode:@"TOGGLE1"
                                                   purchaseAmount:[NSDecimalNumber decimalNumberWithString:@"50"]
                                                    discountedOut:nil
                                                            error:&applyErr];
    XCTAssertFalse(ok);
    XCTAssertEqual(applyErr.code, CPCouponErrorExpired);

    // Re-activate
    BOOL activated = [[CPCouponService sharedService] activateCouponWithUUID:uuid error:nil];
    XCTAssertTrue(activated);

    // Apply should now succeed
    BOOL ok2 = [[CPCouponService sharedService] applyCouponWithCode:@"TOGGLE1"
                                                    purchaseAmount:[NSDecimalNumber decimalNumberWithString:@"50"]
                                                     discountedOut:nil
                                                             error:nil];
    XCTAssertTrue(ok2);
}

// ---------------------------------------------------------------------------
// 14. fetchActiveCoupons only returns valid, active coupons
// ---------------------------------------------------------------------------
- (void)testFetchActiveCouponsFiltersCorrectly {
    [self _createCouponWithCode:@"ACTIVE1" type:CPCouponDiscountTypeFixed value:@"5"];

    NSDate *yesterday = [NSDate dateWithTimeIntervalSinceNow:-86400];
    NSDate *twoDaysAgo = [NSDate dateWithTimeIntervalSinceNow:-172800];
    [[CPCouponService sharedService] createCouponWithCode:@"EXPIRED2"
                                              description:nil
                                             discountType:CPCouponDiscountTypeFixed
                                            discountValue:[NSDecimalNumber decimalNumberWithString:@"5"]
                                                minAmount:nil
                                              maxDiscount:nil
                                                 maxUsage:nil
                                           effectiveStart:twoDaysAgo
                                             effectiveEnd:yesterday
                                                    error:nil];

    NSArray *active = [[CPCouponService sharedService] fetchActiveCoupons];
    BOOL foundActive1 = NO;
    BOOL foundExpired2 = NO;
    for (NSManagedObject *c in active) {
        NSString *code = [c valueForKey:@"code"];
        if ([code isEqualToString:@"ACTIVE1"])   foundActive1 = YES;
        if ([code isEqualToString:@"EXPIRED2"])  foundExpired2 = YES;
    }
    XCTAssertTrue(foundActive1,   @"Active non-expired coupon should appear in fetchActiveCoupons");
    XCTAssertFalse(foundExpired2, @"Expired coupon should not appear in fetchActiveCoupons");
}

// ---------------------------------------------------------------------------
// 15. Permission denied for non-admin user
// ---------------------------------------------------------------------------
- (void)testCreateCouponDeniedForNonAdmin {
    [self loginAs:@"technician" password:kCouponTestPass];
    NSError *err = nil;
    NSString *uuid = [[CPCouponService sharedService]
                      createCouponWithCode:@"NOADMIN"
                               description:nil
                              discountType:CPCouponDiscountTypeFixed
                             discountValue:[NSDecimalNumber decimalNumberWithString:@"5"]
                                 minAmount:nil
                               maxDiscount:nil
                                  maxUsage:nil
                            effectiveStart:nil
                              effectiveEnd:nil
                                     error:&err];
    XCTAssertNil(uuid, @"Non-admin should not be able to create coupons");
    XCTAssertEqual(err.code, CPCouponErrorPermission);
}

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

- (NSString *)_createCouponWithCode:(NSString *)code type:(NSString *)type value:(NSString *)value {
    return [[CPCouponService sharedService] createCouponWithCode:code
                                                     description:nil
                                                    discountType:type
                                                   discountValue:[NSDecimalNumber decimalNumberWithString:value]
                                                       minAmount:nil
                                                     maxDiscount:nil
                                                        maxUsage:nil
                                                  effectiveStart:nil
                                                    effectiveEnd:nil
                                                           error:nil];
}

@end
