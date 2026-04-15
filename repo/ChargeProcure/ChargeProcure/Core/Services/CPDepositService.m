#import "CPDepositService.h"
#import "CPCoreDataStack.h"
#import "CPAuthService.h"
#import "CPRBACService.h"
#import "CPAuditService.h"
#import <CoreData/CoreData.h>

NSString * const CPDepositErrorDomain   = @"com.chargeprocure.deposit";
NSString * const CPDepositStatusPending  = @"Pending";
NSString * const CPDepositStatusCaptured = @"Captured";
NSString * const CPDepositStatusReleased = @"Released";
NSString * const CPDepositStatusFailed   = @"Failed";

@implementation CPDepositService

#pragma mark - Singleton

+ (instancetype)sharedService {
    static CPDepositService *_shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _shared = [[CPDepositService alloc] init];
    });
    return _shared;
}

#pragma mark - Permission Helper

- (BOOL)currentUserCanManageDeposits {
    CPRBACService *rbac = [CPRBACService sharedService];
    // Deposits are finance/admin-level operations; require Invoice approval or admin
    return [[CPAuthService sharedService].currentUserRole isEqualToString:@"Administrator"] ||
           [rbac currentUserCanPerform:CPActionApprove onResource:CPResourceInvoice];
}

#pragma mark - Create

- (nullable NSString *)createDepositForChargerID:(NSString *)chargerID
                                     customerRef:(nullable NSString *)customerRef
                                   depositAmount:(NSDecimalNumber *)depositAmount
                                  preAuthAmount:(NSDecimalNumber *)preAuthAmount
                                           notes:(nullable NSString *)notes
                                           error:(NSError **)error {
    if (![self currentUserCanManageDeposits]) {
        if (error) {
            *error = [NSError errorWithDomain:CPDepositErrorDomain
                                         code:CPDepositErrorPermission
                                     userInfo:@{NSLocalizedDescriptionKey: @"Insufficient permissions to manage deposits."}];
        }
        return nil;
    }

    if (!chargerID.length) {
        if (error) {
            *error = [NSError errorWithDomain:CPDepositErrorDomain
                                         code:CPDepositErrorInvalidAmount
                                     userInfo:@{NSLocalizedDescriptionKey: @"Charger ID is required."}];
        }
        return nil;
    }

    NSDecimalNumber *zero = [NSDecimalNumber zero];
    if ([depositAmount compare:zero] == NSOrderedAscending ||
        [preAuthAmount compare:zero] == NSOrderedAscending) {
        if (error) {
            *error = [NSError errorWithDomain:CPDepositErrorDomain
                                         code:CPDepositErrorInvalidAmount
                                     userInfo:@{NSLocalizedDescriptionKey: @"Deposit and pre-auth amounts must be non-negative."}];
        }
        return nil;
    }

    __block NSString *newUUID = nil;
    __block NSError *saveError = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);

    NSManagedObjectContext *ctx = [[CPCoreDataStack sharedStack] newBackgroundContext];
    [ctx performBlock:^{
        NSManagedObject *deposit = [NSEntityDescription
            insertNewObjectForEntityForName:@"DepositTracking"
                     inManagedObjectContext:ctx];
        newUUID = [[NSUUID UUID] UUIDString];
        [deposit setValue:newUUID      forKey:@"uuid"];
        [deposit setValue:chargerID    forKey:@"chargerID"];
        [deposit setValue:customerRef  forKey:@"customerRef"];
        [deposit setValue:depositAmount forKey:@"depositAmount"];
        [deposit setValue:preAuthAmount forKey:@"preAuthAmount"];
        [deposit setValue:CPDepositStatusPending forKey:@"status"];
        [deposit setValue:notes         forKey:@"notes"];
        // Record creation time in capturedAt as "pending since"
        [deposit setValue:[NSDate date]  forKey:@"capturedAt"];

        NSError *err = nil;
        if (![ctx save:&err]) {
            saveError = err;
            newUUID = nil;
        }
        dispatch_semaphore_signal(sem);
    }];

    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    if (error && saveError) *error = saveError;

    if (newUUID) {
        [[CPAuditService sharedService] logAction:@"deposit_created"
                                         resource:@"DepositTracking"
                                       resourceID:newUUID
                                           detail:[NSString stringWithFormat:
                                                   @"Charger=%@ Amount=%@ PreAuth=%@",
                                                   chargerID, depositAmount, preAuthAmount]];
    }
    return newUUID;
}

#pragma mark - State Transitions

- (BOOL)captureDepositWithUUID:(NSString *)depositUUID error:(NSError **)error {
    return [self _transitionDepositUUID:depositUUID
                            fromStatus:CPDepositStatusPending
                              toStatus:CPDepositStatusCaptured
                              dateKey:@"capturedAt"
                             auditKey:@"deposit_captured"
                                error:error];
}

- (BOOL)releaseDepositWithUUID:(NSString *)depositUUID error:(NSError **)error {
    return [self _transitionDepositUUID:depositUUID
                            fromStatus:nil            // allow Pending or Captured
                              toStatus:CPDepositStatusReleased
                              dateKey:@"releasedAt"
                             auditKey:@"deposit_released"
                                error:error];
}

- (BOOL)markDepositFailedWithUUID:(NSString *)depositUUID error:(NSError **)error {
    return [self _transitionDepositUUID:depositUUID
                            fromStatus:CPDepositStatusPending
                              toStatus:CPDepositStatusFailed
                              dateKey:nil
                             auditKey:@"deposit_failed"
                                error:error];
}

- (BOOL)_transitionDepositUUID:(NSString *)depositUUID
                    fromStatus:(nullable NSString *)allowedStatus
                      toStatus:(NSString *)newStatus
                       dateKey:(nullable NSString *)dateKey
                      auditKey:(NSString *)auditKey
                         error:(NSError **)error {
    if (![self currentUserCanManageDeposits]) {
        if (error) {
            *error = [NSError errorWithDomain:CPDepositErrorDomain
                                         code:CPDepositErrorPermission
                                     userInfo:@{NSLocalizedDescriptionKey: @"Insufficient permissions."}];
        }
        return NO;
    }

    __block BOOL success = NO;
    __block NSError *opError = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);

    NSManagedObjectContext *ctx = [[CPCoreDataStack sharedStack] newBackgroundContext];
    [ctx performBlock:^{
        NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"DepositTracking"];
        req.predicate = [NSPredicate predicateWithFormat:@"uuid == %@", depositUUID];
        req.fetchLimit = 1;
        NSError *fetchErr = nil;
        NSManagedObject *deposit = [[ctx executeFetchRequest:req error:&fetchErr] firstObject];

        if (!deposit) {
            opError = [NSError errorWithDomain:CPDepositErrorDomain
                                          code:CPDepositErrorNotFound
                                      userInfo:@{NSLocalizedDescriptionKey: @"Deposit not found."}];
            dispatch_semaphore_signal(sem);
            return;
        }

        NSString *currentStatus = [deposit valueForKey:@"status"];
        if (allowedStatus && ![currentStatus isEqualToString:allowedStatus]) {
            opError = [NSError errorWithDomain:CPDepositErrorDomain
                                          code:CPDepositErrorInvalidState
                                      userInfo:@{NSLocalizedDescriptionKey:
                                                 [NSString stringWithFormat:
                                                  @"Deposit is in '%@' state; expected '%@'.",
                                                  currentStatus, allowedStatus]}];
            dispatch_semaphore_signal(sem);
            return;
        }

        [deposit setValue:newStatus forKey:@"status"];
        if (dateKey) {
            [deposit setValue:[NSDate date] forKey:dateKey];
        }

        NSError *saveErr = nil;
        success = [ctx save:&saveErr];
        if (!success) opError = saveErr;
        dispatch_semaphore_signal(sem);
    }];

    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    if (error && opError) *error = opError;

    if (success) {
        [[CPAuditService sharedService] logAction:auditKey
                                         resource:@"DepositTracking"
                                       resourceID:depositUUID
                                           detail:[NSString stringWithFormat:@"NewStatus=%@", newStatus]];
    }
    return success;
}

#pragma mark - Fetch

- (NSArray<NSManagedObject *> *)fetchAllDeposits {
    NSManagedObjectContext *ctx = [CPCoreDataStack sharedStack].mainContext;
    NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"DepositTracking"];
    req.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"capturedAt" ascending:NO]];
    req.fetchBatchSize = 50;
    NSError *err = nil;
    return [ctx executeFetchRequest:req error:&err] ?: @[];
}

- (NSArray<NSManagedObject *> *)fetchDepositsForChargerID:(NSString *)chargerID {
    NSManagedObjectContext *ctx = [CPCoreDataStack sharedStack].mainContext;
    NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"DepositTracking"];
    req.predicate = [NSPredicate predicateWithFormat:@"chargerID == %@", chargerID];
    req.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"capturedAt" ascending:NO]];
    req.fetchBatchSize = 50;
    NSError *err = nil;
    return [ctx executeFetchRequest:req error:&err] ?: @[];
}

- (nullable NSManagedObject *)fetchDepositWithUUID:(NSString *)uuid {
    NSManagedObjectContext *ctx = [CPCoreDataStack sharedStack].mainContext;
    NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"DepositTracking"];
    req.predicate = [NSPredicate predicateWithFormat:@"uuid == %@", uuid];
    req.fetchLimit = 1;
    NSError *err = nil;
    return [[ctx executeFetchRequest:req error:&err] firstObject];
}

@end
