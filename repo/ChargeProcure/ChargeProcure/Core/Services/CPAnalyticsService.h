#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const CPAnomalyDetectedNotification;

/// Result of streak calculation
@interface CPStreakResult : NSObject
@property (nonatomic) NSInteger currentStreak;
@property (nonatomic) NSInteger longestStreak;
@property (nonatomic, strong, nullable) NSDate *lastActiveDate;
@end

/// Heatmap cell
@interface CPHeatmapCell : NSObject
@property (nonatomic) NSInteger hour;    // 0-23
@property (nonatomic) NSInteger weekday; // 1=Sun ... 7=Sat
@property (nonatomic) NSInteger count;
@property (nonatomic) CGFloat normalizedIntensity; // 0.0 - 1.0
@end

/// Anomaly result
@interface CPAnomalyResult : NSObject
@property (nonatomic, strong) NSDate *detectedAt;
@property (nonatomic, copy) NSString *anomalyType;   // "gap" | "volatility"
@property (nonatomic, copy) NSString *description;
@property (nonatomic) CGFloat severity;
@end

@interface CPAnalyticsService : NSObject

+ (instancetype)sharedService;

/// Compatibility wrapper used by older analytics dashboards.
- (void)fetchStreakData:(void(^)(NSInteger currentStreak, NSInteger longestStreak, NSError *_Nullable error))completion;

/// Compatibility wrapper used by older analytics dashboards.
- (void)fetchProcurementStages:(void(^)(NSArray<NSDictionary *> *_Nullable stages, NSError *_Nullable error))completion;

/// Compatibility wrapper used by older analytics dashboards.
- (void)fetchChargerHeatmapData:(void(^)(NSArray<NSArray<NSNumber *> *> *_Nullable grid, NSError *_Nullable error))completion;

/// Compatibility wrapper used by older analytics dashboards.
- (void)fetchAnomalies:(void(^)(NSArray<NSDictionary *> *_Nullable anomalies, NSError *_Nullable error))completion;

/// Consecutive-day activity streak (based on ChargerEvents or AuditEvents).
- (CPStreakResult *)calculateActivityStreakForResource:(NSString *)resource;

/// Completion rate per procurement stage.
- (NSDictionary<NSString *, NSNumber *> *)procurementCompletionRates;

/// Heatmap of charger events by hour/weekday.
- (NSArray<CPHeatmapCell *> *)chargerEventHeatmap;

/// Trend analysis: event counts over 7, 30, or 90 days.
- (NSDictionary *)trendAnalysisForDays:(NSInteger)days resource:(NSString *)resource;

/// Anomaly detection: gaps > 72h or volatility > 3x 30-day moving average.
- (NSArray<CPAnomalyResult *> *)detectAnomalies;

/// Comparison: command counts by charger/group.
- (NSDictionary *)commandCountsByCharger;

/// Cache invalidation — call when new events are logged.
- (void)invalidateCache;

@end

NS_ASSUME_NONNULL_END
