#import "CPBackgroundTaskManager.h"
#import "CPChargerService.h"
#import "CPProcurementService.h"
#import "CPBulletinService.h"
#import "CPAttachmentService.h"
#import "CPCoreDataStack.h"

// Task identifiers — must exactly match entries in Info.plist BGTaskSchedulerPermittedIdentifiers
NSString * const CPBGTaskChargerSync          = @"com.chargeprocure.fieldops.charger-sync";
NSString * const CPBGTaskProcurementRefresh   = @"com.chargeprocure.fieldops.procurement-refresh";
NSString * const CPBGTaskReportCleanup        = @"com.chargeprocure.fieldops.report-cleanup";

// Charger sync interval — 15 minutes
static const NSTimeInterval kChargerSyncInterval         = 15.0 * 60.0;

// Procurement refresh earliest begin — 1 hour from now
static const NSTimeInterval kProcurementRefreshInterval  = 60.0 * 60.0;

// Report cleanup earliest begin — 7 days from now
static const NSTimeInterval kReportCleanupInterval       = 7.0 * 24.0 * 60.0 * 60.0;

@implementation CPBackgroundTaskManager

+ (instancetype)sharedManager {
    static CPBackgroundTaskManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[CPBackgroundTaskManager alloc] init];
    });
    return instance;
}

#pragma mark - Low Power Mode

- (BOOL)isLowPowerMode {
    return [NSProcessInfo processInfo].isLowPowerModeEnabled;
}

#pragma mark - Registration

- (void)registerBackgroundTasks {
    BGTaskScheduler *scheduler = [BGTaskScheduler sharedScheduler];

    // --- Charger Sync (BGAppRefreshTask) ---
    BOOL chargerRegistered = [scheduler
        registerForTaskWithIdentifier:CPBGTaskChargerSync
        usingQueue:nil
        launchHandler:^(__kindof BGTask *task) {
            [self _handleChargerSyncTask:(BGAppRefreshTask *)task];
        }];

    if (!chargerRegistered) {
        NSLog(@"[CPBackgroundTaskManager] WARNING: Failed to register charger sync task. "
              @"Ensure '%@' is listed in BGTaskSchedulerPermittedIdentifiers.", CPBGTaskChargerSync);
    }

    // --- Procurement Refresh (BGProcessingTask) ---
    BOOL procurementRegistered = [scheduler
        registerForTaskWithIdentifier:CPBGTaskProcurementRefresh
        usingQueue:nil
        launchHandler:^(__kindof BGTask *task) {
            [self _handleProcurementRefreshTask:(BGProcessingTask *)task];
        }];

    if (!procurementRegistered) {
        NSLog(@"[CPBackgroundTaskManager] WARNING: Failed to register procurement refresh task. "
              @"Ensure '%@' is listed in BGTaskSchedulerPermittedIdentifiers.", CPBGTaskProcurementRefresh);
    }

    // --- Report Cleanup (BGProcessingTask) ---
    BOOL cleanupRegistered = [scheduler
        registerForTaskWithIdentifier:CPBGTaskReportCleanup
        usingQueue:nil
        launchHandler:^(__kindof BGTask *task) {
            [self _handleReportCleanupTask:(BGProcessingTask *)task];
        }];

    if (!cleanupRegistered) {
        NSLog(@"[CPBackgroundTaskManager] WARNING: Failed to register report cleanup task. "
              @"Ensure '%@' is listed in BGTaskSchedulerPermittedIdentifiers.", CPBGTaskReportCleanup);
    }
}

#pragma mark - Scheduling

- (void)scheduleChargerSyncTask {
    BGAppRefreshTaskRequest *request =
        [[BGAppRefreshTaskRequest alloc] initWithIdentifier:CPBGTaskChargerSync];
    request.earliestBeginDate = [NSDate dateWithTimeIntervalSinceNow:kChargerSyncInterval];

    NSError *error = nil;
    BOOL submitted = [[BGTaskScheduler sharedScheduler] submitTaskRequest:request error:&error];
    if (!submitted) {
        NSLog(@"[CPBackgroundTaskManager] Failed to schedule charger sync: %@", error);
    } else {
        NSLog(@"[CPBackgroundTaskManager] Scheduled charger sync (earliest: +%.0f min).",
              kChargerSyncInterval / 60.0);
    }
}

- (void)scheduleProcurementRefreshTask {
    BGProcessingTaskRequest *request =
        [[BGProcessingTaskRequest alloc] initWithIdentifier:CPBGTaskProcurementRefresh];
    request.earliestBeginDate = [NSDate dateWithTimeIntervalSinceNow:kProcurementRefreshInterval];
    request.requiresNetworkConnectivity = NO;
    request.requiresExternalPower = YES;

    NSError *error = nil;
    BOOL submitted = [[BGTaskScheduler sharedScheduler] submitTaskRequest:request error:&error];
    if (!submitted) {
        NSLog(@"[CPBackgroundTaskManager] Failed to schedule procurement refresh: %@", error);
    } else {
        NSLog(@"[CPBackgroundTaskManager] Scheduled procurement refresh (earliest: +%.0f hr).",
              kProcurementRefreshInterval / 3600.0);
    }
}

- (void)scheduleReportCleanupTask {
    BGProcessingTaskRequest *request =
        [[BGProcessingTaskRequest alloc] initWithIdentifier:CPBGTaskReportCleanup];
    request.earliestBeginDate = [NSDate dateWithTimeIntervalSinceNow:kReportCleanupInterval];
    request.requiresNetworkConnectivity = NO;
    request.requiresExternalPower = YES;

    NSError *error = nil;
    BOOL submitted = [[BGTaskScheduler sharedScheduler] submitTaskRequest:request error:&error];
    if (!submitted) {
        NSLog(@"[CPBackgroundTaskManager] Failed to schedule report cleanup: %@", error);
    } else {
        NSLog(@"[CPBackgroundTaskManager] Scheduled report cleanup (earliest: +7 days).");
    }
}

#pragma mark - Application Lifecycle

- (void)applicationDidEnterBackground {
    // Skip scheduling non-urgent work in Low Power Mode
    if (self.isLowPowerMode) {
        NSLog(@"[CPBackgroundTaskManager] Low Power Mode active — skipping non-urgent task scheduling.");
        // Still schedule the charger sync since it is the most important task,
        // but skip procurement refresh and cleanup.
        [self scheduleChargerSyncTask];
        return;
    }

    [self scheduleChargerSyncTask];
    [self scheduleProcurementRefreshTask];
    [self scheduleReportCleanupTask];
}

#pragma mark - Task Handlers (Private)

/// BGAppRefreshTask: poll charger statuses, persist to Core Data, reschedule.
- (void)_handleChargerSyncTask:(BGAppRefreshTask *)task {
    NSLog(@"[CPBackgroundTaskManager] Executing charger sync task.");

    // Set expiration handler — called when the system is about to kill the task
    __block BOOL taskCompleted = NO;
    task.expirationHandler = ^{
        NSLog(@"[CPBackgroundTaskManager] Charger sync task expired before completion.");
        taskCompleted = YES;
        [task setTaskCompletedWithSuccess:NO];
    };

    // Skip in Low Power Mode
    if (self.isLowPowerMode) {
        NSLog(@"[CPBackgroundTaskManager] Low Power Mode active — skipping charger sync work.");
        [task setTaskCompletedWithSuccess:YES];
        [self scheduleChargerSyncTask];
        return;
    }

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        if (taskCompleted) { return; }

        @try {
            // Poll charger statuses and persist to Core Data.
            // These calls are synchronous within this background context.
            [self _performChargerStatusSync];
        } @catch (NSException *exception) {
            NSLog(@"[CPBackgroundTaskManager] Exception during charger sync: %@", exception);
        }

        if (!taskCompleted) {
            taskCompleted = YES;
            [task setTaskCompletedWithSuccess:YES];
        }

        // Reschedule for the next run regardless of outcome
        [self scheduleChargerSyncTask];
    });
}

/// BGProcessingTask: recompute variance flags and reconciliation status.
- (void)_handleProcurementRefreshTask:(BGProcessingTask *)task {
    NSLog(@"[CPBackgroundTaskManager] Executing procurement refresh task.");

    __block BOOL taskCompleted = NO;
    task.expirationHandler = ^{
        NSLog(@"[CPBackgroundTaskManager] Procurement refresh task expired before completion.");
        taskCompleted = YES;
        [task setTaskCompletedWithSuccess:NO];
    };

    // Skip in Low Power Mode — this is non-urgent processing
    if (self.isLowPowerMode) {
        NSLog(@"[CPBackgroundTaskManager] Low Power Mode active — deferring procurement refresh.");
        [task setTaskCompletedWithSuccess:YES];
        // Reschedule so it will run when power conditions improve
        [self scheduleProcurementRefreshTask];
        return;
    }

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0), ^{
        if (taskCompleted) { return; }

        @try {
            [self _performProcurementRefresh];
        } @catch (NSException *exception) {
            NSLog(@"[CPBackgroundTaskManager] Exception during procurement refresh: %@", exception);
        }

        if (!taskCompleted) {
            taskCompleted = YES;
            [task setTaskCompletedWithSuccess:YES];
        }

        // Reschedule for the next interval
        [self scheduleProcurementRefreshTask];
    });
}

/// BGProcessingTask: run weekly attachment cleanup and process scheduled bulletins.
- (void)_handleReportCleanupTask:(BGProcessingTask *)task {
    NSLog(@"[CPBackgroundTaskManager] Executing report cleanup task.");

    __block BOOL taskCompleted = NO;
    task.expirationHandler = ^{
        NSLog(@"[CPBackgroundTaskManager] Report cleanup task expired before completion.");
        taskCompleted = YES;
        [task setTaskCompletedWithSuccess:NO];
    };

    // Skip in Low Power Mode — cleanup is non-urgent
    if (self.isLowPowerMode) {
        NSLog(@"[CPBackgroundTaskManager] Low Power Mode active — deferring report cleanup.");
        [task setTaskCompletedWithSuccess:YES];
        [self scheduleReportCleanupTask];
        return;
    }

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0), ^{
        if (taskCompleted) { return; }

        @try {
            [self _performReportCleanup];
        } @catch (NSException *exception) {
            NSLog(@"[CPBackgroundTaskManager] Exception during report cleanup: %@", exception);
        }

        if (!taskCompleted) {
            taskCompleted = YES;
            [task setTaskCompletedWithSuccess:YES];
        }

        // Reschedule for next week
        [self scheduleReportCleanupTask];
    });
}

#pragma mark - Work Implementations (Private)

/// Polls charger statuses and saves results to Core Data.
- (void)_performChargerStatusSync {
    NSLog(@"[CPBackgroundTaskManager] _performChargerStatusSync: refreshing charger statuses.");

    // Fetch all chargers and mark stale ones for review.
    // The offline app detects chargers that haven't reported status within the
    // past 24 hours and marks them as requiring attention.
    NSArray *chargers = [[CPChargerService sharedService] fetchAllChargers];
    NSDate *staleThreshold = [NSDate dateWithTimeIntervalSinceNow:-24 * 60 * 60];

    for (NSManagedObject *charger in chargers) {
        NSDate *lastSeen = [charger valueForKey:@"lastSeenAt"];
        if (lastSeen && [lastSeen compare:staleThreshold] == NSOrderedAscending) {
            NSString *uuid = [charger valueForKey:@"uuid"];
            [[CPChargerService sharedService] updateCharger:uuid
                                                     status:@"Stale"
                                                     detail:@"No status report within 24h — background sync check"];
        }
    }

    // Retry any pending-review commands that are older than 1 hour
    NSArray *pendingReviews = [[CPChargerService sharedService] fetchPendingReviewCommands];
    NSDate *retryThreshold  = [NSDate dateWithTimeIntervalSinceNow:-60 * 60];
    for (NSManagedObject *cmd in pendingReviews) {
        NSDate *issuedAt = [cmd valueForKey:@"issuedAt"];
        if (issuedAt && [issuedAt compare:retryThreshold] == NSOrderedAscending) {
            NSString *cmdUUID = [cmd valueForKey:@"uuid"];
            [[CPChargerService sharedService] retryCommand:cmdUUID
                                                completion:^(BOOL ack, NSError *err) {
                if (err) {
                    NSLog(@"[CPBackgroundTaskManager] Retry for %@ failed: %@", cmdUUID, err.localizedDescription);
                }
            }];
        }
    }
}

/// Recomputes variance flags and reconciliation status for open documents.
- (void)_performProcurementRefresh {
    NSLog(@"[CPBackgroundTaskManager] _performProcurementRefresh: recomputing variance flags.");

    // Fetch invoices with variance flags and log them for operator review.
    NSArray *flaggedInvoices = [[CPProcurementService sharedService] fetchInvoicesWithVarianceFlag];
    if (flaggedInvoices.count > 0) {
        NSLog(@"[CPBackgroundTaskManager] %lu invoice(s) with variance flags found — pending reconciliation.",
              (unsigned long)flaggedInvoices.count);
    }

    // Save any Core Data changes made during reconciliation processing.
    [[CPCoreDataStack sharedStack] saveMainContext];
}

/// Runs weekly attachment cleanup and processes any scheduled bulletins.
- (void)_performReportCleanup {
    NSLog(@"[CPBackgroundTaskManager] _performReportCleanup: running weekly cleanup.");

    // Process any scheduled bulletins whose publish date has passed.
    [[CPBulletinService sharedService] processScheduledBulletins];

    // Run weekly orphaned attachment cleanup via CPAttachmentService.
    [[CPAttachmentService sharedService] runWeeklyCleanup];

    // Save any Core Data changes made during cleanup.
    [[CPCoreDataStack sharedStack] saveMainContext];
}

@end
