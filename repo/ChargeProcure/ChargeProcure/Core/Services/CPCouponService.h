#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const CPCouponErrorDomain;
FOUNDATION_EXPORT NSString * const CPCouponDiscountTypePercentage;
FOUNDATION_EXPORT NSString * const CPCouponDiscountTypeFixed;

typedef NS_ENUM(NSInteger, CPCouponError) {
    CPCouponErrorNotFound        = 8001,
    CPCouponErrorInvalidCode     = 8002,
    CPCouponErrorDuplicateCode   = 8003,
    CPCouponErrorInvalidValue    = 8004,
    CPCouponErrorExpired         = 8005,
    CPCouponErrorMaxUsageReached = 8006,
    CPCouponErrorPermission      = 8007,
    CPCouponErrorSaveFailed      = 8008,
};

@interface CPCouponService : NSObject

+ (instancetype)sharedService;

/// Returns YES if the current user is permitted to manage (create/activate/deactivate) coupon packages.
- (BOOL)currentUserCanManageCoupons;

/// Create a new coupon package. Admin only.
/// Returns the new coupon UUID on success or nil on failure.
- (nullable NSString *)createCouponWithCode:(NSString *)code
                                description:(nullable NSString *)description
                               discountType:(NSString *)discountType
                              discountValue:(NSDecimalNumber *)discountValue
                                  minAmount:(nullable NSDecimalNumber *)minAmount
                                 maxDiscount:(nullable NSDecimalNumber *)maxDiscount
                                   maxUsage:(nullable NSNumber *)maxUsage
                             effectiveStart:(nullable NSDate *)effectiveStart
                               effectiveEnd:(nullable NSDate *)effectiveEnd
                                      error:(NSError **)error;

/// Activate a coupon (sets isActive = YES).
- (BOOL)activateCouponWithUUID:(NSString *)couponUUID error:(NSError **)error;

/// Deactivate a coupon (sets isActive = NO).
- (BOOL)deactivateCouponWithUUID:(NSString *)couponUUID error:(NSError **)error;

/// Increment usage count for a coupon when applied. Returns NO and an error if
/// the coupon is inactive, expired, or has reached maxUsage.
- (BOOL)applyCouponWithCode:(NSString *)code
             purchaseAmount:(NSDecimalNumber *)purchaseAmount
              discountedOut:(NSDecimalNumber *__nullable *__nullable)discountedAmount
                      error:(NSError **)error;

/// Fetch all coupons sorted by code.
- (NSArray<NSManagedObject *> *)fetchAllCoupons;

/// Fetch only active, currently valid coupons.
- (NSArray<NSManagedObject *> *)fetchActiveCoupons;

/// Fetch a single coupon by UUID. Returns nil if not found.
- (nullable NSManagedObject *)fetchCouponWithUUID:(NSString *)uuid;

/// Fetch a single coupon by code. Returns nil if not found.
- (nullable NSManagedObject *)fetchCouponWithCode:(NSString *)code;

@end

NS_ASSUME_NONNULL_END
