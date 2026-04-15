#import "CPChargerService.h"
#import "CPAuditService.h"
#import "CPAuthService.h"
#import "../CoreData/CPCoreDataStack.h"
#import "../Utilities/CPIDGenerator.h"
#import <CoreData/CoreData.h>

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

NSString * const CPChargerServiceErrorDomain       = @"com.chargeprocure.charger";
NSString * const CPChargerStatusChangedNotification = @"CPChargerStatusChangedNotification";
NSString * const CPCommandAcknowledgedNotification  = @"CPCommandAcknowledgedNotification";

static const NSTimeInterval kCommandTimeoutInterval = 8.0;

// ---------------------------------------------------------------------------
// Private interface
// ---------------------------------------------------------------------------

@interface CPChargerService ()

/// Tracks active command timers keyed by commandUUID → dispatch_source_t.
@property (nonatomic, strong) NSMutableDictionary<NSString *, dispatch_source_t> *activeTimers;
/// Tracks completion blocks keyed by commandUUID.
@property (nonatomic, strong) NSMutableDictionary<NSString *, void (^)(BOOL, NSString *, NSError *)> *pendingCompletions;
/// Serialises access to the above two dictionaries.
@property (nonatomic, strong) dispatch_queue_t timerQueue;

@end

// ---------------------------------------------------------------------------
// Implementation
// ---------------------------------------------------------------------------

@implementation CPChargerService

#pragma mark - Singleton

+ (instancetype)sharedService {
    static CPChargerService *_shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _shared = [[CPChargerService alloc] init];
    });
    return _shared;
}

#pragma mark - Initialization

- (instancetype)init {
    self = [super init];
    if (self) {
        _activeTimers      = [NSMutableDictionary dictionary];
        _pendingCompletions = [NSMutableDictionary dictionary];
        _timerQueue        = dispatch_queue_create("com.chargeprocure.charger.timerQueue",
                                                   DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

#pragma mark - Fetch All Chargers

- (NSArray *)fetchAllChargers {
    __block NSArray *results = @[];
    NSManagedObjectContext *ctx = [[CPCoreDataStack sharedStack] mainContext];
    [ctx performBlockAndWait:^{
        NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"Charger"];
        req.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"location" ascending:YES]];
        NSError *err = nil;
        results = [ctx executeFetchRequest:req error:&err];
        if (err) {
            NSLog(@"[CPChargerService] fetchAllChargers error: %@", err.localizedDescription);
        }
    }];
    return results ?: @[];
}

#pragma mark - Fetch Single Charger

- (nullable id)fetchChargerWithUUID:(NSString *)uuid {
    if (!uuid.length) return nil;

    __block id result = nil;
    NSManagedObjectContext *ctx = [[CPCoreDataStack sharedStack] mainContext];
    [ctx performBlockAndWait:^{
        NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"Charger"];
        req.predicate    = [NSPredicate predicateWithFormat:@"uuid == %@", uuid];
        req.fetchLimit   = 1;
        NSError *err = nil;
        NSArray *arr = [ctx executeFetchRequest:req error:&err];
        result = arr.firstObject;
    }];
    return result;
}

#pragma mark - Update Charger Status

- (void)updateCharger:(NSString *)chargerUUID
               status:(NSString *)status
               detail:(nullable NSString *)detail {
    NSParameterAssert(chargerUUID.length > 0);
    NSParameterAssert(status.length > 0);

    // RBAC: require Charger.update permission
    if (![[CPAuthService sharedService] currentUserHasPermission:@"charger.update"]) {
        [[CPAuditService sharedService] logAction:@"access_denied"
                                         resource:@"Charger"
                                       resourceID:chargerUUID
                                           detail:[NSString stringWithFormat:
                                                   @"updateCharger denied: insufficient role (attempted status=%@)", status]];
        return;
    }

    [[CPCoreDataStack sharedStack] performBackgroundTask:^(NSManagedObjectContext *ctx) {
        // --- Fetch the charger ---
        NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"Charger"];
        req.predicate  = [NSPredicate predicateWithFormat:@"uuid == %@", chargerUUID];
        req.fetchLimit = 1;
        NSError *err = nil;
        NSArray *arr = [ctx executeFetchRequest:req error:&err];
        NSManagedObject *charger = arr.firstObject;

        if (!charger) {
            NSLog(@"[CPChargerService] updateCharger: no charger found for UUID %@", chargerUUID);
            return;
        }

        NSString *previousStatus = [charger valueForKey:@"status"] ?: @"Unknown";

        // --- Update the charger ---
        [charger setValue:status         forKey:@"status"];
        [charger setValue:[NSDate date]  forKey:@"lastSeenAt"];

        // --- Create immutable ChargerEvent ---
        NSManagedObject *event = [NSEntityDescription insertNewObjectForEntityForName:@"ChargerEvent"
                                                               inManagedObjectContext:ctx];
        [event setValue:[CPIDGenerator generateUUID] forKey:@"uuid"];
        [event setValue:chargerUUID                  forKey:@"chargerID"];
        [event setValue:@"StatusUpdate"              forKey:@"eventType"];
        [event setValue:previousStatus               forKey:@"previousStatus"];
        [event setValue:status                       forKey:@"newStatus"];
        [event setValue:detail                       forKey:@"detail"];
        [event setValue:[NSDate date]                forKey:@"occurredAt"];
        [event setValue:charger                      forKey:@"charger"];

        // Save is handled by performBackgroundTask
        NSError *saveErr = nil;
        [ctx save:&saveErr];
        if (saveErr) {
            NSLog(@"[CPChargerService] updateCharger save error: %@", saveErr.localizedDescription);
        }

        // --- Audit ---
        [[CPAuditService sharedService] logAction:@"charger_status_updated"
                                         resource:@"Charger"
                                       resourceID:chargerUUID
                                           detail:[NSString stringWithFormat:@"Status: %@ → %@%@",
                                                   previousStatus, status,
                                                   detail ? [NSString stringWithFormat:@" (%@)", detail] : @""]];

        // --- Notification on main queue ---
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter]
             postNotificationName:CPChargerStatusChangedNotification
             object:self
             userInfo:@{@"chargerUUID": chargerUUID, @"status": status}];
        });
    }];
}

#pragma mark - Issue Command

- (void)issueCommandToCharger:(NSString *)chargerUUID
                  commandType:(NSString *)commandType
                   parameters:(nullable NSDictionary *)parameters
                   completion:(void (^)(BOOL acknowledged, NSString *commandUUID, NSError * _Nullable error))completion {
    NSParameterAssert(chargerUUID.length > 0);
    NSParameterAssert(commandType.length > 0);
    NSParameterAssert(completion != nil);

    // RBAC: require Charger.update permission to issue commands
    if (![[CPAuthService sharedService] currentUserHasPermission:@"charger.update"]) {
        NSString *denyID = [[CPIDGenerator sharedGenerator] generateCommandID];
        [[CPAuditService sharedService] logAction:@"access_denied"
                                         resource:@"Charger"
                                       resourceID:chargerUUID
                                           detail:[NSString stringWithFormat:@"issueCommand(%@) denied: insufficient role", commandType]];
        NSError *rbacErr = [NSError errorWithDomain:CPChargerServiceErrorDomain
                                               code:403
                                           userInfo:@{NSLocalizedDescriptionKey: @"Permission denied: Charger.update is required to issue commands."}];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(NO, denyID, rbacErr);
        });
        return;
    }

    // Generate command UUID up front
    NSString *commandUUID = [[CPIDGenerator sharedGenerator] generateCommandID];

    // Serialize parameters to JSON string if provided
    NSString *paramsJSON = nil;
    if (parameters) {
        NSError *jsonErr = nil;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:parameters
                                                           options:0
                                                             error:&jsonErr];
        if (jsonData && !jsonErr) {
            paramsJSON = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        }
    }

    NSString *issuedByUserID = [CPAuthService sharedService].currentUserID;

    // Persist command record as Pending
    [[CPCoreDataStack sharedStack] performBackgroundTask:^(NSManagedObjectContext *ctx) {
        // Verify charger exists
        NSFetchRequest *chargerReq = [NSFetchRequest fetchRequestWithEntityName:@"Charger"];
        chargerReq.predicate  = [NSPredicate predicateWithFormat:@"uuid == %@", chargerUUID];
        chargerReq.fetchLimit = 1;
        NSError *fetchErr = nil;
        NSArray *chargers = [ctx executeFetchRequest:chargerReq error:&fetchErr];
        NSManagedObject *charger = chargers.firstObject;

        if (!charger) {
            NSError *noChargerErr = [NSError errorWithDomain:CPChargerServiceErrorDomain
                                                        code:404
                                                    userInfo:@{NSLocalizedDescriptionKey:
                                                                   [NSString stringWithFormat:@"Charger not found: %@", chargerUUID]}];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, commandUUID, noChargerErr);
            });
            return;
        }

        // Create Command entity
        NSManagedObject *command = [NSEntityDescription insertNewObjectForEntityForName:@"Command"
                                                                 inManagedObjectContext:ctx];
        [command setValue:commandUUID      forKey:@"uuid"];
        [command setValue:chargerUUID      forKey:@"chargerID"];
        [command setValue:commandType      forKey:@"commandType"];
        [command setValue:paramsJSON       forKey:@"parameters"];
        [command setValue:[NSDate date]    forKey:@"issuedAt"];
        [command setValue:@"Pending"       forKey:@"status"];
        [command setValue:issuedByUserID   forKey:@"issuedByUserID"];
        [command setValue:charger          forKey:@"charger"];

        NSError *saveErr = nil;
        [ctx save:&saveErr];
        if (saveErr) {
            NSLog(@"[CPChargerService] issueCommand save error: %@", saveErr.localizedDescription);
        }

        [[CPAuditService sharedService] logAction:@"command_issued"
                                         resource:@"Command"
                                       resourceID:commandUUID
                                           detail:[NSString stringWithFormat:@"Type=%@ Charger=%@", commandType, chargerUUID]];
    }];

    // Store completion block
    dispatch_async(_timerQueue, ^{
        self.pendingCompletions[commandUUID] = [completion copy];
    });

    // Start 8-second timeout timer
    [self _startTimeoutTimerForCommand:commandUUID chargerUUID:chargerUUID];

    // Deliver via injected adapter (test) or wait for hardware (production).
    if (self.adapter) {
        [self.adapter sendCommand:commandUUID
                        toCharger:chargerUUID
                      commandType:commandType
                       parameters:parameters
                       completion:^(BOOL success, NSString *failureReason) {
            if (success) {
                [self _handleAcknowledgmentForCommand:commandUUID
                                          chargerUUID:chargerUUID
                                              success:YES];
            } else {
                [self _handleAcknowledgmentForCommand:commandUUID
                                          chargerUUID:chargerUUID
                                              success:NO];
            }
        }];
    } else {
        // No adapter injected — production path. The timeout timer above will
        // fire after kCommandTimeoutInterval seconds if the vendor hardware
        // does not call back through a registered hardware delegate.
        NSLog(@"[CPChargerService] Command %@ sent to charger %@; awaiting hardware ACK or timeout.",
              commandUUID, chargerUUID);
    }
}

#pragma mark - Timeout Timer Management

- (void)_startTimeoutTimerForCommand:(NSString *)commandUUID
                          chargerUUID:(NSString *)chargerUUID {
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,
                                                     0, 0, _timerQueue);
    NSTimeInterval timeout = kCommandTimeoutInterval;
#if DEBUG
    if (self.commandTimeoutIntervalOverride > 0) {
        timeout = self.commandTimeoutIntervalOverride;
    }
#endif
    dispatch_source_set_timer(timer,
                              dispatch_time(DISPATCH_TIME_NOW,
                                            (int64_t)(timeout * NSEC_PER_SEC)),
                              DISPATCH_TIME_FOREVER,
                              (uint64_t)(0.1 * NSEC_PER_SEC));

    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(timer, ^{
        [weakSelf _handleTimeoutForCommand:commandUUID chargerUUID:chargerUUID];
    });

    _activeTimers[commandUUID] = timer;
    dispatch_resume(timer);
}

- (void)_cancelTimerForCommand:(NSString *)commandUUID {
    dispatch_async(_timerQueue, ^{
        dispatch_source_t timer = self.activeTimers[commandUUID];
        if (timer) {
            dispatch_source_cancel(timer);
            [self.activeTimers removeObjectForKey:commandUUID];
        }
    });
}

#pragma mark - Acknowledgment Handling

- (void)_handleAcknowledgmentForCommand:(NSString *)commandUUID
                             chargerUUID:(NSString *)chargerUUID
                                 success:(BOOL)success {
    dispatch_async(_timerQueue, ^{
        // Check if there is still a pending completion (i.e. timeout hasn't fired)
        void (^completionBlock)(BOOL, NSString *, NSError *) = self.pendingCompletions[commandUUID];
        if (!completionBlock) {
            // Timeout already fired — ignore late ACK
            return;
        }

        // Cancel the timeout timer
        dispatch_source_t timer = self.activeTimers[commandUUID];
        if (timer) {
            dispatch_source_cancel(timer);
            [self.activeTimers removeObjectForKey:commandUUID];
        }
        [self.pendingCompletions removeObjectForKey:commandUUID];

        if (success) {
            // Update Command status to Acknowledged
            [[CPCoreDataStack sharedStack] performBackgroundTask:^(NSManagedObjectContext *ctx) {
                NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"Command"];
                req.predicate  = [NSPredicate predicateWithFormat:@"uuid == %@", commandUUID];
                req.fetchLimit = 1;
                NSError *err = nil;
                NSArray *arr = [ctx executeFetchRequest:req error:&err];
                NSManagedObject *command = arr.firstObject;
                if (command) {
                    [command setValue:@"Acknowledged"  forKey:@"status"];
                    [command setValue:[NSDate date]     forKey:@"acknowledgedAt"];
                    NSError *saveErr = nil;
                    [ctx save:&saveErr];
                }

                [[CPAuditService sharedService] logAction:@"command_acknowledged"
                                                 resource:@"Command"
                                               resourceID:commandUUID
                                                   detail:[NSString stringWithFormat:@"Charger=%@", chargerUUID]];
            }];

            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter]
                 postNotificationName:CPCommandAcknowledgedNotification
                 object:self
                 userInfo:@{@"commandUUID": commandUUID, @"chargerUUID": chargerUUID}];
                completionBlock(YES, commandUUID, nil);
            });
        } else {
            [self _markCommandFailed:commandUUID
                          chargerUUID:chargerUUID
                               reason:@"Vendor SDK returned failure"
                              newStatus:@"Failed"];
            dispatch_async(dispatch_get_main_queue(), ^{
                NSError *err = [NSError errorWithDomain:CPChargerServiceErrorDomain
                                                   code:500
                                               userInfo:@{NSLocalizedDescriptionKey: @"Command failed: vendor SDK returned failure"}];
                completionBlock(NO, commandUUID, err);
            });
        }
    });
}

#pragma mark - Timeout Handler

- (void)_handleTimeoutForCommand:(NSString *)commandUUID
                      chargerUUID:(NSString *)chargerUUID {
    // Already on _timerQueue
    void (^completionBlock)(BOOL, NSString *, NSError *) = self.pendingCompletions[commandUUID];
    if (!completionBlock) {
        // Already handled (late timer fire)
        return;
    }

    dispatch_source_t timer = self.activeTimers[commandUUID];
    if (timer) {
        dispatch_source_cancel(timer);
        [self.activeTimers removeObjectForKey:commandUUID];
    }
    [self.pendingCompletions removeObjectForKey:commandUUID];

    // Mark command as PendingReview in Core Data
    [self _markCommandFailed:commandUUID
                  chargerUUID:chargerUUID
                       reason:@"Acknowledgment timeout"
                    newStatus:@"PendingReview"];

    dispatch_async(dispatch_get_main_queue(), ^{
        NSError *timeoutErr = [NSError errorWithDomain:CPChargerServiceErrorDomain
                                                  code:408
                                              userInfo:@{NSLocalizedDescriptionKey:
                                                             @"Command timed out waiting for acknowledgment. Marked as Pending Review."}];
        completionBlock(NO, commandUUID, timeoutErr);
    });
}

#pragma mark - Mark Command Failed/PendingReview

- (void)_markCommandFailed:(NSString *)commandUUID
                chargerUUID:(NSString *)chargerUUID
                     reason:(NSString *)reason
                  newStatus:(NSString *)newStatus {
    [[CPCoreDataStack sharedStack] performBackgroundTask:^(NSManagedObjectContext *ctx) {
        NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"Command"];
        req.predicate  = [NSPredicate predicateWithFormat:@"uuid == %@", commandUUID];
        req.fetchLimit = 1;
        NSError *err = nil;
        NSArray *arr = [ctx executeFetchRequest:req error:&err];
        NSManagedObject *command = arr.firstObject;
        if (command) {
            [command setValue:newStatus forKey:@"status"];
            [command setValue:reason    forKey:@"pendingReviewReason"];
            NSError *saveErr = nil;
            [ctx save:&saveErr];
        }

        NSString *action = [newStatus isEqualToString:@"PendingReview"] ? @"command_pending_review" : @"command_failed";
        [[CPAuditService sharedService] logAction:action
                                         resource:@"Command"
                                       resourceID:commandUUID
                                           detail:[NSString stringWithFormat:@"Reason=%@ Charger=%@", reason, chargerUUID]];
    }];
}

#pragma mark - Fetch Pending Review Commands

- (NSArray *)fetchPendingReviewCommands {
    __block NSArray *results = @[];
    NSManagedObjectContext *ctx = [[CPCoreDataStack sharedStack] mainContext];
    [ctx performBlockAndWait:^{
        NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"Command"];
        req.predicate = [NSPredicate predicateWithFormat:@"status == %@", @"PendingReview"];
        req.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"issuedAt" ascending:NO]];
        NSError *err = nil;
        results = [ctx executeFetchRequest:req error:&err];
        if (err) {
            NSLog(@"[CPChargerService] fetchPendingReviewCommands error: %@", err.localizedDescription);
        }
    }];
    return results ?: @[];
}

#pragma mark - Retry Command

- (void)retryCommand:(NSString *)commandUUID
          completion:(void (^)(BOOL acknowledged, NSError * _Nullable error))completion {
    NSParameterAssert(commandUUID.length > 0);
    NSParameterAssert(completion != nil);

    // RBAC: require Charger.update permission to retry commands
    if (![[CPAuthService sharedService] currentUserHasPermission:@"charger.update"]) {
        [[CPAuditService sharedService] logAction:@"access_denied"
                                         resource:@"Command"
                                       resourceID:commandUUID
                                           detail:@"retryCommand denied: insufficient role"];
        NSError *rbacErr = [NSError errorWithDomain:CPChargerServiceErrorDomain
                                               code:403
                                           userInfo:@{NSLocalizedDescriptionKey:
                                                          @"Permission denied: Charger.update is required to retry commands."}];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(NO, rbacErr);
        });
        return;
    }

    // Fetch original command details
    __block NSString *chargerUUID = nil;
    __block NSString *commandType = nil;
    __block NSString *paramsJSON  = nil;

    NSManagedObjectContext *ctx = [[CPCoreDataStack sharedStack] mainContext];
    [ctx performBlockAndWait:^{
        NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"Command"];
        req.predicate  = [NSPredicate predicateWithFormat:@"uuid == %@", commandUUID];
        req.fetchLimit = 1;
        NSError *err = nil;
        NSArray *arr = [ctx executeFetchRequest:req error:&err];
        NSManagedObject *command = arr.firstObject;
        if (command) {
            chargerUUID = [command valueForKey:@"chargerID"];
            commandType = [command valueForKey:@"commandType"];
            paramsJSON  = [command valueForKey:@"parameters"];
        }
    }];

    if (!chargerUUID || !commandType) {
        NSError *notFoundErr = [NSError errorWithDomain:CPChargerServiceErrorDomain
                                                   code:404
                                               userInfo:@{NSLocalizedDescriptionKey:
                                                              [NSString stringWithFormat:@"Command not found: %@", commandUUID]}];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(NO, notFoundErr);
        });
        return;
    }

    // Reset status to Pending before retrying
    [[CPCoreDataStack sharedStack] performBackgroundTask:^(NSManagedObjectContext *bgCtx) {
        NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"Command"];
        req.predicate  = [NSPredicate predicateWithFormat:@"uuid == %@", commandUUID];
        req.fetchLimit = 1;
        NSError *err = nil;
        NSArray *arr = [bgCtx executeFetchRequest:req error:&err];
        NSManagedObject *command = arr.firstObject;
        if (command) {
            [command setValue:@"Pending"  forKey:@"status"];
            [command setValue:nil          forKey:@"pendingReviewReason"];
            [command setValue:[NSDate date] forKey:@"issuedAt"];
            NSError *saveErr = nil;
            [bgCtx save:&saveErr];
        }

        [[CPAuditService sharedService] logAction:@"command_retry"
                                         resource:@"Command"
                                       resourceID:commandUUID
                                           detail:[NSString stringWithFormat:@"Retrying Type=%@ Charger=%@",
                                                   commandType, chargerUUID]];
    }];

    // Store wrapped completion block (same UUID, different wrapper signature)
    void (^wrappedCompletion)(BOOL, NSString *, NSError *) = ^(BOOL ack, NSString *uuid, NSError *err) {
        completion(ack, err);
    };

    dispatch_async(_timerQueue, ^{
        self.pendingCompletions[commandUUID] = [wrappedCompletion copy];
    });

    // Start new 8-second timeout
    [self _startTimeoutTimerForCommand:commandUUID chargerUUID:chargerUUID];

    // Deliver retry via adapter (test) or await hardware (production).
    if (self.adapter) {
        [self.adapter sendCommand:commandUUID
                        toCharger:chargerUUID
                      commandType:commandType
                       parameters:nil
                       completion:^(BOOL success, NSString *failureReason) {
            if (success) {
                [self _handleAcknowledgmentForCommand:commandUUID
                                          chargerUUID:chargerUUID
                                              success:YES];
            } else {
                [self _handleAcknowledgmentForCommand:commandUUID
                                          chargerUUID:chargerUUID
                                              success:NO];
            }
        }];
    } else {
        NSLog(@"[CPChargerService] Retry command %@ sent to charger %@; awaiting hardware ACK or timeout.",
              commandUUID, chargerUUID);
    }
}

#pragma mark - Test Support

#if DEBUG
- (void)cancelAllPendingCommandsForTesting {
    dispatch_sync(_timerQueue, ^{
        for (dispatch_source_t timer in self.activeTimers.allValues) {
            dispatch_source_cancel(timer);
        }
        [self.activeTimers removeAllObjects];
        [self.pendingCompletions removeAllObjects];
    });
    self.commandTimeoutIntervalOverride = 0;
}
#endif

#pragma mark - Register Charger

- (void)registerCharger:(NSString *)chargerUUID
             parameters:(NSDictionary *)parameters {
    NSParameterAssert(chargerUUID.length > 0);
    NSParameterAssert(parameters != nil);

    // RBAC: require Charger.update permission to register or re-register a charger
    if (![[CPAuthService sharedService] currentUserHasPermission:@"charger.update"]) {
        [[CPAuditService sharedService] logAction:@"access_denied"
                                         resource:@"Charger"
                                       resourceID:chargerUUID
                                           detail:@"registerCharger denied: insufficient role"];
        return;
    }

    NSString *paramsJSON = nil;
    NSError *jsonErr = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:parameters options:0 error:&jsonErr];
    if (jsonData && !jsonErr) {
        paramsJSON = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    }

    [[CPCoreDataStack sharedStack] performBackgroundTask:^(NSManagedObjectContext *ctx) {
        // Check if charger already exists
        NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"Charger"];
        req.predicate  = [NSPredicate predicateWithFormat:@"uuid == %@", chargerUUID];
        req.fetchLimit = 1;
        NSError *err = nil;
        NSArray *arr = [ctx executeFetchRequest:req error:&err];
        NSManagedObject *charger = arr.firstObject;

        if (!charger) {
            charger = [NSEntityDescription insertNewObjectForEntityForName:@"Charger"
                                                    inManagedObjectContext:ctx];
            [charger setValue:chargerUUID   forKey:@"uuid"];
            [charger setValue:@"Unknown"    forKey:@"status"];
            [charger setValue:[NSDate date] forKey:@"lastSeenAt"];
        }

        if (paramsJSON) {
            [charger setValue:paramsJSON forKey:@"parameters"];
        }

        // Extract well-known fields from parameters dict
        if (parameters[@"vendorID"]) {
            [charger setValue:parameters[@"vendorID"] forKey:@"vendorID"];
        }
        if (parameters[@"serialNumber"]) {
            [charger setValue:parameters[@"serialNumber"] forKey:@"serialNumber"];
        }
        if (parameters[@"model"]) {
            [charger setValue:parameters[@"model"] forKey:@"model"];
        }
        if (parameters[@"location"]) {
            [charger setValue:parameters[@"location"] forKey:@"location"];
        }
        if (parameters[@"firmwareVersion"]) {
            [charger setValue:parameters[@"firmwareVersion"] forKey:@"firmwareVersion"];
        }

        NSError *saveErr = nil;
        [ctx save:&saveErr];
        if (saveErr) {
            NSLog(@"[CPChargerService] registerCharger save error: %@", saveErr.localizedDescription);
        }

        [[CPAuditService sharedService] logAction:@"charger_registered"
                                         resource:@"Charger"
                                       resourceID:chargerUUID
                                           detail:[NSString stringWithFormat:@"Parameters: %@",
                                                   paramsJSON ?: @"none"]];
    }];
}

@end
