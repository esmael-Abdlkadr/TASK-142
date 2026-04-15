#import <XCTest/XCTest.h>
#import "CPAnalyticsService.h"
#import "CPCoreDataStack.h"
#import "CPTestCoreDataStack.h"
#import "CPTestDataFactory.h"
#import <CoreData/CoreData.h>

@interface CPAnalyticsServiceTests : XCTestCase
@property (nonatomic, strong) NSManagedObjectContext *ctx;
@end

@implementation CPAnalyticsServiceTests

- (void)setUp {
    [super setUp];
    [[CPTestCoreDataStack sharedStack] resetAll];
    self.ctx = [CPTestCoreDataStack sharedStack].mainContext;
    // Clear analytics-relevant entities from the real shared store so tests start clean
    [self clearSharedStoreEntities:@[@"AuditEvent", @"ChargerEvent", @"ProcurementCase"]];
    // Invalidate analytics cache so it re-queries fresh data
    [[CPAnalyticsService sharedService] invalidateCache];
}

- (void)tearDown {
    [[CPTestCoreDataStack sharedStack] resetAll];
    [self clearSharedStoreEntities:@[@"AuditEvent", @"ChargerEvent", @"ProcurementCase"]];
    [[CPAnalyticsService sharedService] invalidateCache];
    [super tearDown];
}

/// Remove all objects for the given entity names from [CPCoreDataStack sharedStack].
- (void)clearSharedStoreEntities:(NSArray<NSString *> *)entityNames {
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [[CPCoreDataStack sharedStack] performBackgroundTask:^(NSManagedObjectContext *ctx) {
        for (NSString *name in entityNames) {
            NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:name];
            req.includesPropertyValues = NO;
            NSArray *objects = [ctx executeFetchRequest:req error:nil];
            for (NSManagedObject *obj in objects) {
                [ctx deleteObject:obj];
            }
        }
        [ctx save:nil];
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
}

/// Insert AuditEvents into [CPCoreDataStack sharedStack] so CPAnalyticsService can read them.
- (void)insertSharedAuditEventsAtDates:(NSArray<NSDate *> *)dates resource:(NSString *)resource {
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [[CPCoreDataStack sharedStack] performBackgroundTask:^(NSManagedObjectContext *ctx) {
        for (NSDate *date in dates) {
            NSManagedObject *event = [NSEntityDescription insertNewObjectForEntityForName:@"AuditEvent"
                                                                   inManagedObjectContext:ctx];
            [event setValue:[[NSUUID UUID] UUIDString] forKey:@"uuid"];
            [event setValue:resource ?: @"test"        forKey:@"resource"];
            [event setValue:@"test_action"             forKey:@"action"];
            [event setValue:date                       forKey:@"occurredAt"];
        }
        [ctx save:nil];
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
}

/// Insert ChargerEvents into [CPCoreDataStack sharedStack] so CPAnalyticsService can read them.
- (void)insertSharedChargerEventsAtDates:(NSArray<NSDate *> *)dates chargerUUID:(NSString *)chargerUUID {
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [[CPCoreDataStack sharedStack] performBackgroundTask:^(NSManagedObjectContext *ctx) {
        for (NSDate *date in dates) {
            NSManagedObject *event = [NSEntityDescription insertNewObjectForEntityForName:@"ChargerEvent"
                                                                   inManagedObjectContext:ctx];
            [event setValue:[[NSUUID UUID] UUIDString] forKey:@"uuid"];
            [event setValue:chargerUUID               forKey:@"chargerID"];
            [event setValue:@"StatusUpdate"           forKey:@"eventType"];
            [event setValue:date                      forKey:@"occurredAt"];
        }
        [ctx save:nil];
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
}

/// Insert ProcurementCase records into [CPCoreDataStack sharedStack].
- (void)insertSharedProcurementCasesWithStages:(NSDictionary<NSString *, NSNumber *> *)stageCounts {
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [[CPCoreDataStack sharedStack] performBackgroundTask:^(NSManagedObjectContext *ctx) {
        for (NSString *stage in stageCounts) {
            NSInteger count = [stageCounts[stage] integerValue];
            for (NSInteger i = 0; i < count; i++) {
                NSManagedObject *procCase = [NSEntityDescription insertNewObjectForEntityForName:@"ProcurementCase"
                                                                          inManagedObjectContext:ctx];
                [procCase setValue:[[NSUUID UUID] UUIDString] forKey:@"uuid"];
                [procCase setValue:stage                      forKey:@"stage"];
                [procCase setValue:[NSDate date]              forKey:@"createdAt"];
            }
        }
        [ctx save:nil];
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
}

// ---------------------------------------------------------------------------
// Helper: insert AuditEvent records into the REAL shared store
// CPAnalyticsService reads from [CPCoreDataStack sharedStack] internally.
// We use the service itself to exercise the full code path.
// ---------------------------------------------------------------------------

/// Insert a ChargerEvent at a given date directly into the shared stack's store.
- (void)insertChargerEventAtDate:(NSDate *)date
                      chargerUUID:(NSString *)chargerUUID
                        inContext:(NSManagedObjectContext *)ctx {
    NSManagedObject *event = [NSEntityDescription insertNewObjectForEntityForName:@"ChargerEvent"
                                                           inManagedObjectContext:ctx];
    [event setValue:[[NSUUID UUID] UUIDString] forKey:@"uuid"];
    [event setValue:chargerUUID               forKey:@"chargerID"];
    [event setValue:@"StatusUpdate"           forKey:@"eventType"];
    [event setValue:date                      forKey:@"occurredAt"];
}

/// Insert an AuditEvent into the shared stack's store.
- (void)insertAuditEventForResource:(NSString *)resource
                              atDate:(NSDate *)date
                           inContext:(NSManagedObjectContext *)ctx {
    NSManagedObject *event = [NSEntityDescription insertNewObjectForEntityForName:@"AuditEvent"
                                                           inManagedObjectContext:ctx];
    [event setValue:[[NSUUID UUID] UUIDString] forKey:@"uuid"];
    [event setValue:resource                   forKey:@"resource"];
    [event setValue:@"test_action"             forKey:@"action"];
    [event setValue:date                       forKey:@"occurredAt"];
}

// ---------------------------------------------------------------------------
// 1. testActivityStreakCalculation — consecutive days = correct streak count
// ---------------------------------------------------------------------------
- (void)testActivityStreakCalculation {
    // Insert AuditEvents for 3 consecutive days into [CPCoreDataStack sharedStack]
    // so that CPAnalyticsService reads real persisted data through its normal code path.
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDate *today     = [cal startOfDayForDate:[NSDate date]];
    NSDate *yesterday = [cal dateByAddingUnit:NSCalendarUnitDay value:-1 toDate:today options:0];
    NSDate *dayBefore = [cal dateByAddingUnit:NSCalendarUnitDay value:-2 toDate:today options:0];

    [self insertSharedAuditEventsAtDates:@[dayBefore, yesterday, today] resource:@"test_streak"];
    [[CPAnalyticsService sharedService] invalidateCache];

    // Call the real service and assert the computed streak equals 3
    CPStreakResult *result = [[CPAnalyticsService sharedService] calculateActivityStreakForResource:nil];
    XCTAssertNotNil(result, @"Streak result should not be nil");
    XCTAssertEqual(result.currentStreak, 3,
                   @"Three consecutive days of AuditEvents should yield a current streak of 3");
}

// ---------------------------------------------------------------------------
// 2. testStreakBrokenByGap — gap of 2 days resets streak
// ---------------------------------------------------------------------------
- (void)testStreakBrokenByGap {
    // Insert AuditEvents 3 days apart into the real shared store.
    // The service should detect the gap and report current streak = 1 (only today counts).
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDate *today        = [cal startOfDayForDate:[NSDate date]];
    NSDate *threeDaysAgo = [cal dateByAddingUnit:NSCalendarUnitDay value:-3 toDate:today options:0];

    [self insertSharedAuditEventsAtDates:@[threeDaysAgo, today] resource:@"test_streak_gap"];
    [[CPAnalyticsService sharedService] invalidateCache];

    CPStreakResult *result = [[CPAnalyticsService sharedService] calculateActivityStreakForResource:nil];
    XCTAssertNotNil(result, @"Streak result should not be nil");
    XCTAssertEqual(result.currentStreak, 1,
                   @"A 3-day gap should reset the streak — only today's event counts (streak = 1)");
}

// ---------------------------------------------------------------------------
// 3. testProcurementCompletionRates — 3 closed + 1 open = 75% completion
// ---------------------------------------------------------------------------
- (void)testProcurementCompletionRates {
    // Insert 3 "Closed" cases and 1 "Open" case into the real shared store,
    // then call the service and verify it reports the correct per-stage rates.
    [self insertSharedProcurementCasesWithStages:@{@"Closed": @3, @"Open": @1}];
    [[CPAnalyticsService sharedService] invalidateCache];

    NSDictionary<NSString *, NSNumber *> *rates =
        [[CPAnalyticsService sharedService] procurementCompletionRates];

    XCTAssertNotNil(rates, @"procurementCompletionRates should not return nil");
    XCTAssertNotNil(rates[@"Closed"], @"Result should contain a 'Closed' key");
    XCTAssertNotNil(rates[@"Open"],   @"Result should contain an 'Open' key");
    XCTAssertEqualWithAccuracy(rates[@"Closed"].doubleValue, 0.75, 0.001,
                               @"3 Closed out of 4 total should yield a Closed rate of 0.75");
    XCTAssertEqualWithAccuracy(rates[@"Open"].doubleValue, 0.25, 0.001,
                               @"1 Open out of 4 total should yield an Open rate of 0.25");

    // Empty store case: service returns an empty dict (no NaN / crash)
    [self clearSharedStoreEntities:@[@"ProcurementCase"]];
    [[CPAnalyticsService sharedService] invalidateCache];
    NSDictionary *emptyRates = [[CPAnalyticsService sharedService] procurementCompletionRates];
    XCTAssertNotNil(emptyRates, @"Service should return a non-nil dict even with no cases");
    XCTAssertEqual(emptyRates.count, (NSUInteger)0,
                   @"Empty store should return an empty rates dictionary");
}

// ---------------------------------------------------------------------------
// 4. testHeatmapHas168Cells — heatmap returns 7x24 = 168 cells
// ---------------------------------------------------------------------------
- (void)testHeatmapHas168Cells {
    // Call chargerEventHeatmap — even with no events, it should return a full 7x24 grid
    NSArray *cells = [[CPAnalyticsService sharedService] chargerEventHeatmap];

    XCTAssertNotNil(cells, @"Heatmap should not be nil");
    XCTAssertEqual(cells.count, (NSUInteger)168,
                   @"Heatmap should always have exactly 7 * 24 = 168 cells");

    // Verify all cells have valid weekday (1-7) and hour (0-23)
    for (CPHeatmapCell *cell in cells) {
        XCTAssertGreaterThanOrEqual(cell.weekday, 1);
        XCTAssertLessThanOrEqual(cell.weekday, 7);
        XCTAssertGreaterThanOrEqual(cell.hour, 0);
        XCTAssertLessThanOrEqual(cell.hour, 23);
        XCTAssertGreaterThanOrEqual(cell.normalizedIntensity, 0.0f);
        XCTAssertLessThanOrEqual(cell.normalizedIntensity, 1.0f);
    }
}

// ---------------------------------------------------------------------------
// 5. testAnomalyDetectedForGap — gap > 72h between events flagged
// ---------------------------------------------------------------------------
- (void)testAnomalyDetectedForGap {
    // Insert two ChargerEvents separated by 73 hours into the real shared store
    // and verify that CPAnalyticsService.detectAnomalies returns a "gap" anomaly.
    NSDate *now    = [NSDate date];
    NSDate *event1 = [now dateByAddingTimeInterval:-(73.0 * 3600.0)]; // 73 hours ago

    [self insertSharedChargerEventsAtDates:@[event1, now] chargerUUID:@"charger-gap-test"];
    [[CPAnalyticsService sharedService] invalidateCache];

    NSArray<CPAnomalyResult *> *anomalies = [[CPAnalyticsService sharedService] detectAnomalies];

    // At least one anomaly of type "gap" must be present
    BOOL foundGap = NO;
    for (CPAnomalyResult *a in anomalies) {
        if ([a.anomalyType isEqualToString:@"gap"]) {
            foundGap = YES;
            break;
        }
    }
    XCTAssertTrue(foundGap,
                  @"A 73-hour gap between ChargerEvents should be reported as a 'gap' anomaly by detectAnomalies");

    // Verify the near-threshold case: two events only 71 hours apart → no gap anomaly
    [self clearSharedStoreEntities:@[@"ChargerEvent"]];
    [[CPAnalyticsService sharedService] invalidateCache];

    NSDate *eventA = [now dateByAddingTimeInterval:-(71.0 * 3600.0)]; // 71 hours ago
    [self insertSharedChargerEventsAtDates:@[eventA, now] chargerUUID:@"charger-nogap-test"];
    [[CPAnalyticsService sharedService] invalidateCache];

    NSArray<CPAnomalyResult *> *noGapAnomalies = [[CPAnalyticsService sharedService] detectAnomalies];
    BOOL foundGapInSmall = NO;
    for (CPAnomalyResult *a in noGapAnomalies) {
        if ([a.anomalyType isEqualToString:@"gap"]) {
            foundGapInSmall = YES;
            break;
        }
    }
    XCTAssertFalse(foundGapInSmall,
                   @"A 71-hour gap between ChargerEvents should NOT be flagged as a gap anomaly");
}

// ---------------------------------------------------------------------------
// 6. testVolatilityAnomalyDetected — 3x moving average spike flagged
// ---------------------------------------------------------------------------
- (void)testVolatilityAnomalyDetected {
    // Strategy: establish a 30-day moving average of 1 event/day by inserting
    // 1 event per day over 31 days, then insert 31 events on a single "spike" day
    // (today minus 1 day so it falls within the 30-day window of the last analysed day).
    // The spike day count (31) > 3 * 1 = 3 → volatility anomaly expected.
    NSDate *now = [NSDate date];
    NSCalendar *cal = [NSCalendar currentCalendar];

    NSMutableArray<NSDate *> *backgroundDates = [NSMutableArray array];
    // One event per day for 32 days ago through 2 days ago (baseline: ~30 events over 30 days = avg ~1/day)
    for (NSInteger d = 32; d >= 2; d--) {
        NSDate *day = [cal dateByAddingUnit:NSCalendarUnitDay value:-(d) toDate:now options:0];
        [backgroundDates addObject:[cal startOfDayForDate:day]];
    }

    // Spike day: yesterday — insert 31 events (exceeds 3 * ~1 = 3)
    NSDate *spikeDay = [cal startOfDayForDate:[cal dateByAddingUnit:NSCalendarUnitDay value:-1 toDate:now options:0]];
    NSMutableArray<NSDate *> *spikeDates = [NSMutableArray array];
    for (NSInteger i = 0; i < 31; i++) {
        // Spread events across the spike day by adding seconds so they all fall on the same calendar day
        [spikeDates addObject:[spikeDay dateByAddingTimeInterval:(double)i * 60.0]];
    }

    NSMutableArray<NSDate *> *allDates = [NSMutableArray arrayWithArray:backgroundDates];
    [allDates addObjectsFromArray:spikeDates];

    [self insertSharedChargerEventsAtDates:allDates chargerUUID:@"charger-volatility-test"];
    [[CPAnalyticsService sharedService] invalidateCache];

    NSArray<CPAnomalyResult *> *anomalies = [[CPAnalyticsService sharedService] detectAnomalies];

    BOOL foundVolatility = NO;
    for (CPAnomalyResult *a in anomalies) {
        if ([a.anomalyType isEqualToString:@"volatility"]) {
            foundVolatility = YES;
            break;
        }
    }
    XCTAssertTrue(foundVolatility,
                  @"A daily count of 31 against a ~1-event/day moving average should trigger a volatility anomaly");
}

// ---------------------------------------------------------------------------
// 7. testTrendDataFor7Days — returns 7 entries with date and count
// ---------------------------------------------------------------------------
- (void)testTrendDataFor7Days {
    [[CPAnalyticsService sharedService] invalidateCache];
    NSDictionary *trendResult = [[CPAnalyticsService sharedService]
                                 trendAnalysisForDays:7 resource:nil];

    XCTAssertNotNil(trendResult, @"Trend result should not be nil");

    NSArray *data = trendResult[@"data"];
    XCTAssertNotNil(data, @"Trend data array should not be nil");
    XCTAssertEqual(data.count, (NSUInteger)7,
                   @"7-day trend should return exactly 7 entries");

    NSNumber *daysParam = trendResult[@"days"];
    XCTAssertEqual(daysParam.integerValue, 7,
                   @"Result should include the days parameter");

    // Each entry must have a 'date' and 'count' key
    for (NSDictionary *entry in data) {
        XCTAssertNotNil(entry[@"date"], @"Each trend entry should have a 'date' key");
        XCTAssertNotNil(entry[@"count"], @"Each trend entry should have a 'count' key");
        XCTAssertTrue([entry[@"date"] isKindOfClass:[NSDate class]],
                      @"'date' should be an NSDate");
        XCTAssertTrue([entry[@"count"] isKindOfClass:[NSNumber class]],
                      @"'count' should be an NSNumber");
    }
}

// ---------------------------------------------------------------------------
// Private helper: calculate streak from sorted array of day-start dates
// ---------------------------------------------------------------------------
- (NSInteger)streakForDates:(NSArray<NSDate *> *)sortedDates {
    if (sortedDates.count == 0) return 0;
    NSCalendar *cal = [NSCalendar currentCalendar];

    // Check if the last date is today or yesterday (active streak)
    NSDate *today = [cal startOfDayForDate:[NSDate date]];
    NSDate *lastDay = sortedDates.lastObject;
    NSDateComponents *diffToToday = [cal components:NSCalendarUnitDay
                                           fromDate:lastDay
                                             toDate:today
                                            options:0];
    if (diffToToday.day > 1) {
        return 0; // streak is broken
    }

    // Count consecutive days backwards from the last date
    NSInteger streak = 1;
    for (NSInteger i = (NSInteger)sortedDates.count - 2; i >= 0; i--) {
        NSDate *prev = sortedDates[i];
        NSDate *curr = sortedDates[i + 1];
        NSDateComponents *diff = [cal components:NSCalendarUnitDay
                                        fromDate:prev
                                          toDate:curr
                                         options:0];
        if (diff.day == 1) {
            streak++;
        } else {
            break;
        }
    }
    return streak;
}

@end
