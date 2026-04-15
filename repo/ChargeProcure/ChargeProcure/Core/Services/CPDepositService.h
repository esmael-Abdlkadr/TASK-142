#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const CPDepositErrorDomain;
FOUNDATION_EXPORT NSString * const CPDepositStatusPending;
FOUNDATION_EXPORT NSString * const CPDepositStatusCaptured;
FOUNDATION_EXPORT NSString * const CPDepositStatusReleased;
FOUNDATION_EXPORT NSString * const CPDepositStatusFailed;

typedef NS_ENUM(NSInteger, CPDepositError) {
    CPDepositErrorNotFound       = 7001,
    CPDepositErrorInvalidState   = 7002,
    CPDepositErrorInvalidAmount  = 7003,
    CPDepositErrorPermission     = 7004,
    CPDepositErrorSaveFailed     = 7005,
};

@interface CPDepositService : NSObject

+ (instancetype)sharedService;

/// Returns YES if the current user has permission to manage deposits.
- (BOOL)currentUserCanManageDeposits;

/// Create a new deposit/pre-auth record for a charger session.
/// Returns the new deposit UUID on success or nil on failure.
- (nullable NSString *)createDepositForChargerID:(NSString *)chargerID
                                     customerRef:(nullable NSString *)customerRef
                                   depositAmount:(NSDecimalNumber *)depositAmount
                                  preAuthAmount:(NSDecimalNumber *)preAuthAmount
                                           notes:(nullable NSString *)notes
                                           error:(NSError **)error;

/// Capture a previously pending pre-authorization.
/// Transitions status from Pending → Captured and records capturedAt timestamp.
- (BOOL)captureDepositWithUUID:(NSString *)depositUUID error:(NSError **)error;

/// Release a deposit (full or partial refund scenario).
/// Transitions status from Pending or Captured → Released and records releasedAt.
- (BOOL)releaseDepositWithUUID:(NSString *)depositUUID error:(NSError **)error;

/// Mark a deposit as failed (e.g. network error during pre-auth).
- (BOOL)markDepositFailedWithUUID:(NSString *)depositUUID error:(NSError **)error;

/// Fetch all deposits, most recent first.
- (NSArray<NSManagedObject *> *)fetchAllDeposits;

/// Fetch deposits for a specific charger.
- (NSArray<NSManagedObject *> *)fetchDepositsForChargerID:(NSString *)chargerID;

/// Fetch a single deposit by UUID. Returns nil if not found.
- (nullable NSManagedObject *)fetchDepositWithUUID:(NSString *)uuid;

@end

NS_ASSUME_NONNULL_END
