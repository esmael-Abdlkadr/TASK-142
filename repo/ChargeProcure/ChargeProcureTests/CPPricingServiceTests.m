#import <XCTest/XCTest.h>
#import "CPPricingService.h"
#import "CPTestCoreDataStack.h"
#import "CPTestDataFactory.h"
#import <CoreData/CoreData.h>

@interface CPPricingServiceTests : XCTestCase
@property (nonatomic, strong) NSManagedObjectContext *ctx;
@end

@implementation CPPricingServiceTests

- (void)setUp {
    [super setUp];
    [[CPTestCoreDataStack sharedStack] resetAll];
    self.ctx = [CPTestCoreDataStack sharedStack].mainContext;
}

- (void)tearDown {
    [[CPTestCoreDataStack sharedStack] resetAll];
    [super tearDown];
}

// ---------------------------------------------------------------------------
// Helper: create a pricing rule through the service (shared store)
// ---------------------------------------------------------------------------
- (NSString *)createRuleForServiceType:(NSString *)serviceType
                           vehicleClass:(nullable NSString *)vehicleClass
                                storeID:(nullable NSString *)storeID
                              basePrice:(NSDecimalNumber *)basePrice
                               tierJSON:(nullable NSString *)tierJSON {
    NSError *err = nil;
    return [[CPPricingService sharedService]
            createPricingRuleWithServiceType:serviceType
            vehicleClass:vehicleClass
            storeID:storeID
            effectiveStart:[NSDate dateWithTimeIntervalSinceNow:-3600]
            effectiveEnd:nil
            basePrice:basePrice
            tierJSON:tierJSON
            notes:nil
            error:&err];
}

// ---------------------------------------------------------------------------
// 1. testExactMatchPricingRule — exact vehicleClass+storeID match returned
// ---------------------------------------------------------------------------
- (void)testExactMatchPricingRule {
    [self createRuleForServiceType:@"Level2"
                       vehicleClass:nil
                            storeID:nil
                          basePrice:[NSDecimalNumber decimalNumberWithString:@"5.00"]
                           tierJSON:nil];

    NSString *specificUUID = [self createRuleForServiceType:@"Level2"
                                                vehicleClass:@"Fleet"
                                                     storeID:@"STORE-001"
                                                   basePrice:[NSDecimalNumber decimalNumberWithString:@"4.00"]
                                                    tierJSON:nil];
    XCTAssertNotNil(specificUUID, @"Specific rule should be created");

    id rule = [[CPPricingService sharedService]
               activePricingRuleForServiceType:@"Level2"
               vehicleClass:@"Fleet"
               storeID:@"STORE-001"
               date:[NSDate date]];

    XCTAssertNotNil(rule, @"A matching rule should be found");
    if (rule) {
        XCTAssertEqualObjects([rule valueForKey:@"vehicleClass"], @"Fleet",
                              @"Exact match should have vehicleClass=Fleet");
        XCTAssertEqualObjects([rule valueForKey:@"storeID"], @"STORE-001",
                              @"Exact match should have storeID=STORE-001");
    }
}

// ---------------------------------------------------------------------------
// 2. testFallbackToLessSpecificRule
// ---------------------------------------------------------------------------
- (void)testFallbackToLessSpecificRule {
    [self createRuleForServiceType:@"DCFC"
                       vehicleClass:nil
                            storeID:nil
                          basePrice:[NSDecimalNumber decimalNumberWithString:@"10.00"]
                           tierJSON:nil];

    id rule = [[CPPricingService sharedService]
               activePricingRuleForServiceType:@"DCFC"
               vehicleClass:@"Passenger"
               storeID:@"STORE-999"
               date:[NSDate date]];

    XCTAssertNotNil(rule, @"Should fall back to generic rule when no exact match exists");
    XCTAssertEqualObjects([rule valueForKey:@"basePrice"],
                          [NSDecimalNumber decimalNumberWithString:@"10.00"],
                          @"Fallback rule should have the generic base price");
}

// ---------------------------------------------------------------------------
// 3. testInactiveRuleExcluded
// ---------------------------------------------------------------------------
- (void)testInactiveRuleExcluded {
    NSError *err = nil;
    NSString *expiredUUID = [[CPPricingService sharedService]
                             createPricingRuleWithServiceType:@"Level2Special"
                             vehicleClass:nil
                             storeID:nil
                             effectiveStart:[NSDate dateWithTimeIntervalSinceNow:-7200]
                             effectiveEnd:[NSDate dateWithTimeIntervalSinceNow:-3600]
                             basePrice:[NSDecimalNumber decimalNumberWithString:@"7.00"]
                             tierJSON:nil
                             notes:nil
                             error:&err];
    XCTAssertNotNil(expiredUUID, @"Expired rule record should be created successfully");

    id rule = [[CPPricingService sharedService]
               activePricingRuleForServiceType:@"Level2Special"
               vehicleClass:nil
               storeID:nil
               date:[NSDate date]];

    XCTAssertNil(rule,
                 @"Rule with effectiveEnd in the past must not be returned as active");
}

// ---------------------------------------------------------------------------
// 4. testTieredPricingFirstTier — duration 30min returns first tier price
// ---------------------------------------------------------------------------
- (void)testTieredPricingFirstTier {
    NSString *tierJSON = @"["
        @"{\"maxDuration\": 3600, \"price\": 2.50},"
        @"{\"maxDuration\": null, \"price\": 5.00}"
        @"]";

    [self createRuleForServiceType:@"Level2Tiered"
                       vehicleClass:nil
                            storeID:nil
                          basePrice:[NSDecimalNumber decimalNumberWithString:@"3.00"]
                           tierJSON:tierJSON];

    NSError *err = nil;
    NSDecimalNumber *price = [[CPPricingService sharedService]
                              calculatePriceForServiceType:@"Level2Tiered"
                              vehicleClass:nil
                              storeID:nil
                              date:[NSDate date]
                              duration:1800
                              error:&err];

    XCTAssertNil(err, @"Price calculation should succeed");
    XCTAssertNotNil(price, @"Price should not be nil");
    XCTAssertFalse([price isEqual:[NSDecimalNumber notANumber]], @"Price should not be NaN");
    XCTAssertEqualObjects(price, [NSDecimalNumber decimalNumberWithString:@"2.50"],
                          @"30-min duration should return first tier price $2.50");
}

// ---------------------------------------------------------------------------
// 5. testTieredPricingSecondTier — duration 90min returns second tier price
// ---------------------------------------------------------------------------
- (void)testTieredPricingSecondTier {
    NSString *tierJSON = @"["
        @"{\"maxDuration\": 3600, \"price\": 2.50},"
        @"{\"maxDuration\": null, \"price\": 5.00}"
        @"]";

    [self createRuleForServiceType:@"Level2Tiered90"
                       vehicleClass:nil
                            storeID:nil
                          basePrice:[NSDecimalNumber decimalNumberWithString:@"3.00"]
                           tierJSON:tierJSON];

    NSError *err = nil;
    NSDecimalNumber *price = [[CPPricingService sharedService]
                              calculatePriceForServiceType:@"Level2Tiered90"
                              vehicleClass:nil
                              storeID:nil
                              date:[NSDate date]
                              duration:5400
                              error:&err];

    XCTAssertNil(err, @"Price calculation should succeed");
    XCTAssertNotNil(price, @"Price should not be nil");
    XCTAssertFalse([price isEqual:[NSDecimalNumber notANumber]], @"Price should not be NaN");
    XCTAssertEqualObjects(price, [NSDecimalNumber decimalNumberWithString:@"5.00"],
                          @"90-min duration should return second tier price $5.00");
}

// ---------------------------------------------------------------------------
// 6. testBasepriceUsedWhenNoTiers
// ---------------------------------------------------------------------------
- (void)testBasepriceUsedWhenNoTiers {
    NSDecimalNumber *basePrice = [NSDecimalNumber decimalNumberWithString:@"3.75"];
    [self createRuleForServiceType:@"NoTierService"
                       vehicleClass:nil
                            storeID:nil
                          basePrice:basePrice
                           tierJSON:nil];

    NSError *err = nil;
    NSDecimalNumber *price = [[CPPricingService sharedService]
                              calculatePriceForServiceType:@"NoTierService"
                              vehicleClass:nil
                              storeID:nil
                              date:[NSDate date]
                              duration:3600
                              error:&err];

    XCTAssertNil(err, @"Price calculation should succeed with no tiers");
    XCTAssertEqualObjects(price, basePrice,
                          @"When no tiers are defined, basePrice ($3.75) should be returned");
}

// ---------------------------------------------------------------------------
// 7. testRuleVersioning — new rule creation increments version for same serviceType
// ---------------------------------------------------------------------------
- (void)testRuleVersioning {
    NSString *uuid1 = [self createRuleForServiceType:@"VersionedService"
                                         vehicleClass:nil
                                              storeID:nil
                                            basePrice:[NSDecimalNumber decimalNumberWithString:@"1.00"]
                                             tierJSON:nil];
    XCTAssertNotNil(uuid1, @"First rule should be created");

    NSString *uuid2 = [self createRuleForServiceType:@"VersionedService"
                                         vehicleClass:nil
                                              storeID:nil
                                            basePrice:[NSDecimalNumber decimalNumberWithString:@"2.00"]
                                             tierJSON:nil];
    XCTAssertNotNil(uuid2, @"Second rule should be created");
    XCTAssertNotEqualObjects(uuid1, uuid2, @"Two rule versions should have different UUIDs");

    NSArray *history = [[CPPricingService sharedService]
                        fetchPricingRuleHistoryForServiceType:@"VersionedService"];
    XCTAssertEqual(history.count, (NSUInteger)2, @"History should contain 2 versions");

    if (history.count >= 2) {
        NSNumber *v1 = [history[0] valueForKey:@"version"];
        NSNumber *v2 = [history[1] valueForKey:@"version"];
        XCTAssertGreaterThan(v1.integerValue, v2.integerValue,
                             @"History should be sorted descending by version");
        XCTAssertEqual(v1.integerValue, 2, @"Latest version should be 2");
        XCTAssertEqual(v2.integerValue, 1, @"Earlier version should be 1");
    }
}

@end
