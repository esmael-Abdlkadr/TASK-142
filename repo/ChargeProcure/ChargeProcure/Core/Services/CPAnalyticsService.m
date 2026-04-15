#import "CPAnalyticsService.h"
#import "CPCoreDataStack.h"
#import <CoreData/CoreData.h>
#import <CoreGraphics/CoreGraphics.h>

NSString * const CPAnomalyDetectedNotification = @"CPAnomalyDetectedNotification";

// Cache keys
static NSString * const kCacheKeyStreak             = @"streak_%@";
static NSString * const kCacheKeyCompletionRates    = @"completionRates";
static NSString * const kCacheKeyHeatmap            = @"heatmap";
static NSString * const kCacheKeyTrend              = @"trend_%ld_%@";
static NSString * const kCacheKeyAnomalies          = @"anomalies";
static NSString * const kCacheKeyCommandCounts      = @"commandCounts";

static const NSTimeInterval kCacheTTL = 60.0; // 60-second TTL

#pragma mark - CPStreakResult

@implementation CPStreakResult
@end

#pragma mark - CPHeatmapCell

@implementation CPHeatmapCell
@end

#pragma mark - CPAnomalyResult

@implementation CPAnomalyResult
@end

#pragma mark - Cache Entry

@interface CPCacheEntry : NSObject
@property (nonatomic, strong) id value;
@property (nonatomic, strong) NSDate *cachedAt;
@end

@implementation CPCacheEntry
- (BOOL)isExpired {
    return [[NSDate date] timeIntervalSinceDate:self.cachedAt] > kCacheTTL;
}
@end

#pragma mark - CPAnalyticsService

@interface CPAnalyticsService ()
@property (nonatomic, strong) NSCache *cache;
@property (nonatomic, strong) dispatch_queue_t backgroundQueue;
@end

@implementation CPAnalyticsService

+ (instancetype)sharedService {
    static CPAnalyticsService *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[CPAnalyticsService alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _cache = [[NSCache alloc] init];
        _cache.countLimit = 50;
        _backgroundQueue = dispatch_queue_create("com.chargeprocure.analytics", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

#pragma mark - Cache Helpers

- (nullable id)cachedValueForKey:(NSString *)key {
    CPCacheEntry *entry = [self.cache objectForKey:key];
    if (entry && ![entry isExpired]) {
        return entry.value;
    }
    return nil;
}

- (void)setCacheValue:(id)value forKey:(NSString *)key {
    CPCacheEntry *entry = [[CPCacheEntry alloc] init];
    entry.value = value;
    entry.cachedAt = [NSDate date];
    [self.cache setObject:entry forKey:key];
}

- (void)invalidateCache {
    [self.cache removeAllObjects];
}

#pragma mark - Compatibility Wrappers

- (void)fetchStreakData:(void(^)(NSInteger currentStreak, NSInteger longestStreak, NSError *_Nullable error))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        CPStreakResult *result = [self calculateActivityStreakForResource:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(result.currentStreak, result.longestStreak, nil);
        });
    });
}

- (void)fetchProcurementStages:(void(^)(NSArray<NSDictionary *> *_Nullable stages, NSError *_Nullable error))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSDictionary<NSString *, NSNumber *> *rates = [self procurementCompletionRates];
        NSMutableArray<NSDictionary *> *stages = [NSMutableArray arrayWithCapacity:rates.count];
        for (NSString *name in [[rates allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)]) {
            [stages addObject:@{
                @"name": name ?: @"Unknown",
                @"completionRate": rates[name] ?: @0
            }];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion([stages copy], nil);
        });
    });
}

- (void)fetchChargerHeatmapData:(void(^)(NSArray<NSArray<NSNumber *> *> *_Nullable grid, NSError *_Nullable error))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray<CPHeatmapCell *> *cells = [self chargerEventHeatmap];
        NSMutableArray<NSMutableArray<NSNumber *> *> *grid = [NSMutableArray arrayWithCapacity:7];
        for (NSInteger row = 0; row < 7; row++) {
            NSMutableArray<NSNumber *> *hours = [NSMutableArray arrayWithCapacity:24];
            for (NSInteger hour = 0; hour < 24; hour++) {
                [hours addObject:@0];
            }
            [grid addObject:hours];
        }

        for (CPHeatmapCell *cell in cells) {
            NSInteger row = MAX(0, MIN(6, cell.weekday - 1));
            NSInteger col = MAX(0, MIN(23, cell.hour));
            grid[row][col] = @(cell.normalizedIntensity);
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion([grid copy], nil);
        });
    });
}

- (void)fetchAnomalies:(void(^)(NSArray<NSDictionary *> *_Nullable anomalies, NSError *_Nullable error))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray<CPAnomalyResult *> *results = [self detectAnomalies];
        NSMutableArray<NSDictionary *> *anomalies = [NSMutableArray arrayWithCapacity:results.count];
        for (CPAnomalyResult *result in results) {
            NSString *severity = @"low";
            if (result.severity >= 0.85f) {
                severity = @"critical";
            } else if (result.severity >= 0.6f) {
                severity = @"high";
            } else if (result.severity >= 0.3f) {
                severity = @"medium";
            }

            [anomalies addObject:@{
                @"type": result.anomalyType ?: @"Unknown",
                @"description": result.description ?: @"",
                @"severity": severity
            }];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion([anomalies copy], nil);
        });
    });
}

#pragma mark - Activity Streak

- (CPStreakResult *)calculateActivityStreakForResource:(NSString *)resource {
    NSString *cacheKey = [NSString stringWithFormat:kCacheKeyStreak, resource ?: @"all"];
    id cached = [self cachedValueForKey:cacheKey];
    if (cached) {
        return cached;
    }

    __block CPStreakResult *result = [[CPStreakResult alloc] init];

    dispatch_sync(self.backgroundQueue, ^{
        NSManagedObjectContext *context = [[CPCoreDataStack sharedStack] newBackgroundContext];
        [context performBlockAndWait:^{
            // Fetch AuditEvent dates sorted ascending
            NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"AuditEvent"];
            if (resource && resource.length > 0) {
                request.predicate = [NSPredicate predicateWithFormat:@"resource == %@", resource];
            }
            request.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"occurredAt" ascending:YES]];
            request.resultType = NSDictionaryResultType;
            request.propertiesToFetch = @[@"occurredAt"];

            NSError *error = nil;
            NSArray *rows = [context executeFetchRequest:request error:&error];
            if (!rows || rows.count == 0) {
                result.currentStreak = 0;
                result.longestStreak = 0;
                result.lastActiveDate = nil;
                return;
            }

            // Extract unique calendar days
            NSCalendar *calendar = [NSCalendar currentCalendar];
            NSMutableOrderedSet *uniqueDays = [NSMutableOrderedSet orderedSet];
            for (NSDictionary *row in rows) {
                NSDate *date = row[@"occurredAt"];
                if (!date) continue;
                NSDateComponents *comps = [calendar components:(NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay)
                                                      fromDate:date];
                NSDate *dayStart = [calendar dateFromComponents:comps];
                if (dayStart) {
                    [uniqueDays addObject:dayStart];
                }
            }

            NSArray *sortedDays = [[uniqueDays array] sortedArrayUsingSelector:@selector(compare:)];
            if (sortedDays.count == 0) {
                result.currentStreak = 0;
                result.longestStreak = 0;
                result.lastActiveDate = nil;
                return;
            }

            // Calculate streaks
            NSInteger currentStreak = 1;
            NSInteger longestStreak = 1;
            NSInteger runningStreak = 1;

            for (NSInteger i = 1; i < (NSInteger)sortedDays.count; i++) {
                NSDate *prev = sortedDays[i - 1];
                NSDate *curr = sortedDays[i];
                NSDateComponents *diffComps = [calendar components:NSCalendarUnitDay
                                                          fromDate:prev
                                                            toDate:curr
                                                           options:0];
                if (diffComps.day == 1) {
                    runningStreak++;
                    if (runningStreak > longestStreak) {
                        longestStreak = runningStreak;
                    }
                } else {
                    runningStreak = 1;
                }
            }

            // Check if current streak reaches today or yesterday
            NSDate *lastDay = sortedDays.lastObject;
            NSDate *today = [calendar startOfDayForDate:[NSDate date]];
            NSDateComponents *diffToToday = [calendar components:NSCalendarUnitDay
                                                        fromDate:lastDay
                                                          toDate:today
                                                         options:0];
            if (diffToToday.day <= 1) {
                // Streak is still active
                currentStreak = runningStreak;
            } else {
                currentStreak = 0;
            }

            result.currentStreak = currentStreak;
            result.longestStreak = longestStreak;
            result.lastActiveDate = lastDay;
        }];
    });

    [self setCacheValue:result forKey:cacheKey];

    dispatch_async(dispatch_get_main_queue(), ^{
        // Result already computed synchronously, main-thread access is safe via the returned object
    });

    return result;
}

#pragma mark - Procurement Completion Rates

- (NSDictionary<NSString *, NSNumber *> *)procurementCompletionRates {
    id cached = [self cachedValueForKey:kCacheKeyCompletionRates];
    if (cached) {
        return cached;
    }

    __block NSDictionary *result = @{};

    dispatch_sync(self.backgroundQueue, ^{
        NSManagedObjectContext *context = [[CPCoreDataStack sharedStack] newBackgroundContext];
        [context performBlockAndWait:^{
            NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"ProcurementCase"];
            NSError *error = nil;
            NSArray *cases = [context executeFetchRequest:request error:&error];

            if (!cases || cases.count == 0) {
                result = @{};
                return;
            }

            NSInteger total = cases.count;
            NSMutableDictionary *stageCounts = [NSMutableDictionary dictionary];

            for (NSManagedObject *procCase in cases) {
                NSString *stage = [procCase valueForKey:@"stage"] ?: @"Unknown";
                NSInteger count = [stageCounts[stage] integerValue];
                stageCounts[stage] = @(count + 1);
            }

            NSMutableDictionary *rates = [NSMutableDictionary dictionary];
            for (NSString *stage in stageCounts) {
                CGFloat rate = (CGFloat)[stageCounts[stage] integerValue] / (CGFloat)total;
                rates[stage] = @(rate);
            }
            result = [rates copy];
        }];
    });

    [self setCacheValue:result forKey:kCacheKeyCompletionRates];
    return result;
}

#pragma mark - Heatmap

- (NSArray<CPHeatmapCell *> *)chargerEventHeatmap {
    id cached = [self cachedValueForKey:kCacheKeyHeatmap];
    if (cached) {
        return cached;
    }

    __block NSArray *result = @[];

    dispatch_sync(self.backgroundQueue, ^{
        NSManagedObjectContext *context = [[CPCoreDataStack sharedStack] newBackgroundContext];
        [context performBlockAndWait:^{
            NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"ChargerEvent"];
            request.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"occurredAt" ascending:YES]];
            request.resultType = NSDictionaryResultType;
            request.propertiesToFetch = @[@"occurredAt"];

            NSError *error = nil;
            NSArray *rows = [context executeFetchRequest:request error:&error];

            // Build 24x7 grid: counts[weekday 1-7][hour 0-23]
            // weekday: 1=Sun ... 7=Sat (NSCalendar convention)
            NSMutableDictionary *grid = [NSMutableDictionary dictionary]; // @"weekday_hour" -> count
            NSInteger maxCount = 0;

            NSCalendar *calendar = [NSCalendar currentCalendar];

            for (NSDictionary *row in rows) {
                NSDate *date = row[@"occurredAt"];
                if (!date) continue;

                NSDateComponents *comps = [calendar components:(NSCalendarUnitHour | NSCalendarUnitWeekday)
                                                      fromDate:date];
                NSInteger hour    = comps.hour;     // 0-23
                NSInteger weekday = comps.weekday;  // 1-7

                NSString *key = [NSString stringWithFormat:@"%ld_%ld", (long)weekday, (long)hour];
                NSInteger current = [grid[key] integerValue];
                current++;
                grid[key] = @(current);
                if (current > maxCount) {
                    maxCount = current;
                }
            }

            // Build full 24x7 grid cells
            NSMutableArray *cells = [NSMutableArray array];
            for (NSInteger weekday = 1; weekday <= 7; weekday++) {
                for (NSInteger hour = 0; hour < 24; hour++) {
                    CPHeatmapCell *cell = [[CPHeatmapCell alloc] init];
                    cell.weekday = weekday;
                    cell.hour    = hour;
                    NSString *key = [NSString stringWithFormat:@"%ld_%ld", (long)weekday, (long)hour];
                    cell.count   = [grid[key] integerValue];
                    cell.normalizedIntensity = (maxCount > 0) ? ((CGFloat)cell.count / (CGFloat)maxCount) : 0.0f;
                    [cells addObject:cell];
                }
            }
            result = [cells copy];
        }];
    });

    [self setCacheValue:result forKey:kCacheKeyHeatmap];
    return result;
}

#pragma mark - Trend Analysis

- (NSDictionary *)trendAnalysisForDays:(NSInteger)days resource:(NSString *)resource {
    NSString *cacheKey = [NSString stringWithFormat:kCacheKeyTrend, (long)days, resource ?: @"all"];
    id cached = [self cachedValueForKey:cacheKey];
    if (cached) {
        return cached;
    }

    __block NSDictionary *result = @{};

    dispatch_sync(self.backgroundQueue, ^{
        NSManagedObjectContext *context = [[CPCoreDataStack sharedStack] newBackgroundContext];
        [context performBlockAndWait:^{
            NSCalendar *calendar = [NSCalendar currentCalendar];
            NSDate *now = [NSDate date];
            NSDate *startDate = [calendar dateByAddingUnit:NSCalendarUnitDay value:-days toDate:now options:0];

            NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"ChargerEvent"];

            NSPredicate *datePredicate = [NSPredicate predicateWithFormat:@"occurredAt >= %@", startDate];
            if (resource && resource.length > 0) {
                NSPredicate *resourcePredicate = [NSPredicate predicateWithFormat:@"chargerID == %@", resource];
                request.predicate = [NSCompoundPredicate andPredicateWithSubpredicates:@[datePredicate, resourcePredicate]];
            } else {
                request.predicate = datePredicate;
            }

            request.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"occurredAt" ascending:YES]];
            request.resultType = NSDictionaryResultType;
            request.propertiesToFetch = @[@"occurredAt"];

            NSError *error = nil;
            NSArray *rows = [context executeFetchRequest:request error:&error];

            // Group counts by day (day-start date)
            NSMutableDictionary *dayCounts = [NSMutableDictionary dictionary];

            // Pre-populate all days in range with 0
            for (NSInteger d = 0; d < days; d++) {
                NSDate *dayDate = [calendar dateByAddingUnit:NSCalendarUnitDay value:-d toDate:now options:0];
                NSDate *dayStart = [calendar startOfDayForDate:dayDate];
                dayCounts[dayStart] = @0;
            }

            for (NSDictionary *row in rows) {
                NSDate *date = row[@"occurredAt"];
                if (!date) continue;
                NSDate *dayStart = [calendar startOfDayForDate:date];
                NSInteger count = [dayCounts[dayStart] integerValue];
                dayCounts[dayStart] = @(count + 1);
            }

            // Build sorted array of {date, count} dictionaries
            NSArray *sortedDays = [[dayCounts allKeys] sortedArrayUsingSelector:@selector(compare:)];
            NSMutableArray *trendArray = [NSMutableArray array];
            for (NSDate *day in sortedDays) {
                [trendArray addObject:@{@"date": day, @"count": dayCounts[day]}];
            }

            NSMutableArray<NSNumber *> *dailyCounts = [NSMutableArray arrayWithCapacity:trendArray.count];
            for (NSDictionary *entry in trendArray) {
                [dailyCounts addObject:entry[@"count"] ?: @0];
            }

            result = @{
                @"days": @(days),
                @"resource": resource ?: @"all",
                @"data": [trendArray copy],
                @"dailyCounts": [dailyCounts copy]
            };
        }];
    });

    [self setCacheValue:result forKey:cacheKey];
    return result;
}

#pragma mark - Anomaly Detection

- (NSArray<CPAnomalyResult *> *)detectAnomalies {
    id cached = [self cachedValueForKey:kCacheKeyAnomalies];
    if (cached) {
        return cached;
    }

    __block NSArray *result = @[];

    dispatch_sync(self.backgroundQueue, ^{
        NSManagedObjectContext *context = [[CPCoreDataStack sharedStack] newBackgroundContext];
        [context performBlockAndWait:^{
            NSCalendar *calendar = [NSCalendar currentCalendar];
            NSDate *now = [NSDate date];
            // Look back 90 days for anomaly detection context
            NSDate *startDate = [calendar dateByAddingUnit:NSCalendarUnitDay value:-90 toDate:now options:0];

            NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"ChargerEvent"];
            request.predicate = [NSPredicate predicateWithFormat:@"occurredAt >= %@", startDate];
            request.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"occurredAt" ascending:YES]];
            request.resultType = NSDictionaryResultType;
            request.propertiesToFetch = @[@"occurredAt"];

            NSError *error = nil;
            NSArray *rows = [context executeFetchRequest:request error:&error];

            NSMutableArray *anomalies = [NSMutableArray array];

            if (!rows || rows.count == 0) {
                result = @[];
                return;
            }

            NSMutableArray *dates = [NSMutableArray array];
            for (NSDictionary *row in rows) {
                NSDate *d = row[@"occurredAt"];
                if (d) [dates addObject:d];
            }

            // --- Gap Detection: intervals > 72 hours ---
            static const NSTimeInterval kGapThreshold = 72.0 * 3600.0; // 72 hours in seconds

            for (NSInteger i = 1; i < (NSInteger)dates.count; i++) {
                NSDate *prev = dates[i - 1];
                NSDate *curr = dates[i];
                NSTimeInterval gap = [curr timeIntervalSinceDate:prev];
                if (gap > kGapThreshold) {
                    CPAnomalyResult *anomaly = [[CPAnomalyResult alloc] init];
                    anomaly.detectedAt  = curr;
                    anomaly.anomalyType = @"gap";
                    anomaly.description = [NSString stringWithFormat:
                        @"Gap of %.1f hours detected between events (threshold: 72h)",
                        gap / 3600.0];
                    // Severity: normalized by how much it exceeds the threshold (cap at 1.0)
                    anomaly.severity = (CGFloat)MIN(gap / (kGapThreshold * 3.0), 1.0);
                    [anomalies addObject:anomaly];
                }
            }

            // --- Volatility Detection: daily count > 3x 30-day moving average ---
            // Build daily counts for last 90 days
            NSMutableDictionary *dayCounts = [NSMutableDictionary dictionary];
            for (NSDate *d in dates) {
                NSDate *dayStart = [calendar startOfDayForDate:d];
                NSInteger count = [dayCounts[dayStart] integerValue];
                dayCounts[dayStart] = @(count + 1);
            }

            NSArray *sortedDayKeys = [[dayCounts allKeys] sortedArrayUsingSelector:@selector(compare:)];

            for (NSInteger i = 0; i < (NSInteger)sortedDayKeys.count; i++) {
                NSDate *day = sortedDayKeys[i];
                NSInteger dayCount = [dayCounts[day] integerValue];

                // Compute 30-day moving average: average of up to 30 days before this day
                NSDate *windowStart = [calendar dateByAddingUnit:NSCalendarUnitDay value:-30 toDate:day options:0];
                NSInteger windowSum   = 0;
                NSInteger windowDays  = 0;

                for (NSDate *prevDay in sortedDayKeys) {
                    if ([prevDay compare:day] == NSOrderedAscending &&
                        [prevDay compare:windowStart] != NSOrderedAscending) {
                        windowSum  += [dayCounts[prevDay] integerValue];
                        windowDays++;
                    }
                }

                if (windowDays > 0) {
                    CGFloat movingAvg = (CGFloat)windowSum / (CGFloat)windowDays;
                    if (movingAvg > 0 && (CGFloat)dayCount > 3.0f * movingAvg) {
                        CPAnomalyResult *anomaly = [[CPAnomalyResult alloc] init];
                        anomaly.detectedAt  = day;
                        anomaly.anomalyType = @"volatility";
                        anomaly.description = [NSString stringWithFormat:
                            @"Daily count %ld exceeds 3x 30-day moving average (%.1f)",
                            (long)dayCount, movingAvg];
                        // Severity: ratio above 3x threshold, capped at 1.0
                        anomaly.severity = (CGFloat)MIN(((CGFloat)dayCount / (3.0f * movingAvg) - 1.0f) / 3.0f, 1.0f);
                        [anomalies addObject:anomaly];
                    }
                }
            }

            result = [anomalies copy];

            // Post notification on main queue if anomalies found
            if (anomalies.count > 0) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[NSNotificationCenter defaultCenter]
                        postNotificationName:CPAnomalyDetectedNotification
                                      object:nil
                                    userInfo:@{@"anomalies": anomalies}];
                });
            }
        }];
    });

    [self setCacheValue:result forKey:kCacheKeyAnomalies];
    return result;
}

#pragma mark - Command Counts by Charger

- (NSDictionary *)commandCountsByCharger {
    id cached = [self cachedValueForKey:kCacheKeyCommandCounts];
    if (cached) {
        return cached;
    }

    __block NSDictionary *result = @{};

    dispatch_sync(self.backgroundQueue, ^{
        NSManagedObjectContext *context = [[CPCoreDataStack sharedStack] newBackgroundContext];
        [context performBlockAndWait:^{
            NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"Command"];
            request.resultType = NSDictionaryResultType;
            request.propertiesToFetch = @[@"chargerID"];
            request.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"chargerID" ascending:YES]];

            NSError *error = nil;
            NSArray *rows = [context executeFetchRequest:request error:&error];

            NSMutableDictionary *counts = [NSMutableDictionary dictionary];
            for (NSDictionary *row in rows) {
                NSString *chargerID = row[@"chargerID"] ?: @"Unknown";
                NSInteger count = [counts[chargerID] integerValue];
                counts[chargerID] = @(count + 1);
            }
            result = [counts copy];
        }];
    });

    [self setCacheValue:result forKey:kCacheKeyCommandCounts];
    return result;
}

@end
