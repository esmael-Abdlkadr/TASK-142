#import <Foundation/Foundation.h>
#import <BackgroundTasks/BackgroundTasks.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const CPBGTaskChargerSync;
FOUNDATION_EXPORT NSString * const CPBGTaskProcurementRefresh;
FOUNDATION_EXPORT NSString * const CPBGTaskReportCleanup;

@interface CPBackgroundTaskManager : NSObject

+ (instancetype)sharedManager;

/// Register all background task handlers with BGTaskScheduler.
- (void)registerBackgroundTasks;

/// Schedule charger sync app refresh task.
- (void)scheduleChargerSyncTask;

/// Schedule procurement refresh processing task.
- (void)scheduleProcurementRefreshTask;

/// Schedule weekly cleanup processing task.
- (void)scheduleReportCleanupTask;

/// Handle app entering background — queue non-urgent work.
- (void)applicationDidEnterBackground;

/// Check if Low Power Mode is active; defers non-urgent tasks.
@property (nonatomic, readonly) BOOL isLowPowerMode;

@end

NS_ASSUME_NONNULL_END
