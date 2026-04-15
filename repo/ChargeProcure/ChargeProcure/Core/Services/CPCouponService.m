#import "CPCouponService.h"
#import "CPCoreDataStack.h"
#import "CPAuthService.h"
#import "CPRBACService.h"
#import "CPAuditService.h"
#import <CoreData/CoreData.h>

NSString * const CPCouponErrorDomain              = @"com.chargeprocure.coupon";
NSString * const CPCouponDiscountTypePercentage    = @"percentage";
NSString * const CPCouponDiscountTypeFixed         = @"fixed";

@implementation CPCouponService

#pragma mark - Singleton

+ (instancetype)sharedService {
    static CPCouponService *_shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _shared = [[CPCouponService alloc] init];
    });
    return _shared;
}

#pragma mark - Permission Helper

- (BOOL)currentUserCanManageCoupons {
    return [[CPAuthService sharedService].currentUserRole isEqualToString:@"Administrator"];
}

#pragma mark - Create

- (nullable NSString *)createCouponWithCode:(NSString *)code
                                description:(nullable NSString *)description
                               discountType:(NSString *)discountType
                              discountValue:(NSDecimalNumber *)discountValue
                                  minAmount:(nullable NSDecimalNumber *)minAmount
                                 maxDiscount:(nullable NSDecimalNumber *)maxDiscount
                                   maxUsage:(nullable NSNumber *)maxUsage
                             effectiveStart:(nullable NSDate *)effectiveStart
                               effectiveEnd:(nullable NSDate *)effectiveEnd
                                      error:(NSError **)error {
    if (![self currentUserCanManageCoupons]) {
        if (error) {
            *error = [NSError errorWithDomain:CPCouponErrorDomain
                                         code:CPCouponErrorPermission
                                     userInfo:@{NSLocalizedDescriptionKey: @"Only administrators can manage coupons."}];
        }
        return nil;
    }

    if (!code.length) {
        if (error) {
            *error = [NSError errorWithDomain:CPCouponErrorDomain
                                         code:CPCouponErrorInvalidCode
                                     userInfo:@{NSLocalizedDescriptionKey: @"Coupon code is required."}];
        }
        return nil;
    }

    if (![discountType isEqualToString:CPCouponDiscountTypePercentage] &&
        ![discountType isEqualToString:CPCouponDiscountTypeFixed]) {
        if (error) {
            *error = [NSError errorWithDomain:CPCouponErrorDomain
                                         code:CPCouponErrorInvalidValue
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                @"discountType must be 'percentage' or 'fixed'."}];
        }
        return nil;
    }

    if ([discountValue compare:[NSDecimalNumber zero]] != NSOrderedDescending) {
        if (error) {
            *error = [NSError errorWithDomain:CPCouponErrorDomain
                                         code:CPCouponErrorInvalidValue
                                     userInfo:@{NSLocalizedDescriptionKey: @"Discount value must be greater than zero."}];
        }
        return nil;
    }

    __block NSString *newUUID = nil;
    __block NSError *opError  = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);

    NSManagedObjectContext *ctx = [[CPCoreDataStack sharedStack] newBackgroundContext];
    [ctx performBlock:^{
        // Enforce unique code
        NSFetchRequest *dupCheck = [NSFetchRequest fetchRequestWithEntityName:@"CouponPackage"];
        dupCheck.predicate = [NSPredicate predicateWithFormat:@"code ==[cd] %@", code];
        dupCheck.fetchLimit = 1;
        NSError *dupErr = nil;
        NSArray *existing = [ctx executeFetchRequest:dupCheck error:&dupErr];
        if (existing.count > 0) {
            opError = [NSError errorWithDomain:CPCouponErrorDomain
                                          code:CPCouponErrorDuplicateCode
                                      userInfo:@{NSLocalizedDescriptionKey:
                                                 [NSString stringWithFormat:@"A coupon with code '%@' already exists.", code]}];
            dispatch_semaphore_signal(sem);
            return;
        }

        NSManagedObject *coupon = [NSEntityDescription
            insertNewObjectForEntityForName:@"CouponPackage"
                     inManagedObjectContext:ctx];
        newUUID = [[NSUUID UUID] UUIDString];
        [coupon setValue:newUUID         forKey:@"uuid"];
        [coupon setValue:code.uppercaseString forKey:@"code"];
        [coupon setValue:description     forKey:@"desc"];
        [coupon setValue:discountType    forKey:@"discountType"];
        [coupon setValue:discountValue   forKey:@"discountValue"];
        [coupon setValue:minAmount ?: [NSDecimalNumber zero] forKey:@"minAmount"];
        [coupon setValue:maxDiscount     forKey:@"maxDiscount"];
        [coupon setValue:@(0)            forKey:@"usageCount"];
        [coupon setValue:maxUsage        forKey:@"maxUsage"];
        [coupon setValue:@(YES)          forKey:@"isActive"];
        [coupon setValue:effectiveStart  forKey:@"effectiveStart"];
        [coupon setValue:effectiveEnd    forKey:@"effectiveEnd"];
        [coupon setValue:[NSDate date]   forKey:@"createdAt"];

        NSError *saveErr = nil;
        if (![ctx save:&saveErr]) {
            opError = saveErr;
            newUUID = nil;
        }
        dispatch_semaphore_signal(sem);
    }];

    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    if (error && opError) *error = opError;

    if (newUUID) {
        [[CPAuditService sharedService] logAction:@"coupon_created"
                                         resource:@"CouponPackage"
                                       resourceID:newUUID
                                           detail:[NSString stringWithFormat:
                                                   @"Code=%@ Type=%@ Value=%@",
                                                   code.uppercaseString, discountType, discountValue]];
    }
    return newUUID;
}

#pragma mark - Activate / Deactivate

- (BOOL)activateCouponWithUUID:(NSString *)couponUUID error:(NSError **)error {
    return [self _setActive:YES forCouponUUID:couponUUID error:error];
}

- (BOOL)deactivateCouponWithUUID:(NSString *)couponUUID error:(NSError **)error {
    return [self _setActive:NO forCouponUUID:couponUUID error:error];
}

- (BOOL)_setActive:(BOOL)active
     forCouponUUID:(NSString *)couponUUID
             error:(NSError **)error {
    if (![self currentUserCanManageCoupons]) {
        if (error) {
            *error = [NSError errorWithDomain:CPCouponErrorDomain
                                         code:CPCouponErrorPermission
                                     userInfo:@{NSLocalizedDescriptionKey: @"Only administrators can manage coupons."}];
        }
        return NO;
    }

    __block BOOL success = NO;
    __block NSError *opError = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);

    NSManagedObjectContext *ctx = [[CPCoreDataStack sharedStack] newBackgroundContext];
    [ctx performBlock:^{
        NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"CouponPackage"];
        req.predicate = [NSPredicate predicateWithFormat:@"uuid == %@", couponUUID];
        req.fetchLimit = 1;
        NSManagedObject *coupon = [[ctx executeFetchRequest:req error:nil] firstObject];
        if (!coupon) {
            opError = [NSError errorWithDomain:CPCouponErrorDomain
                                          code:CPCouponErrorNotFound
                                      userInfo:@{NSLocalizedDescriptionKey: @"Coupon not found."}];
            dispatch_semaphore_signal(sem);
            return;
        }
        [coupon setValue:@(active) forKey:@"isActive"];
        NSError *saveErr = nil;
        success = [ctx save:&saveErr];
        if (!success) opError = saveErr;
        dispatch_semaphore_signal(sem);
    }];

    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    if (error && opError) *error = opError;

    if (success) {
        [[CPAuditService sharedService] logAction:active ? @"coupon_activated" : @"coupon_deactivated"
                                         resource:@"CouponPackage"
                                       resourceID:couponUUID
                                           detail:nil];
    }
    return success;
}

#pragma mark - Apply

- (BOOL)applyCouponWithCode:(NSString *)code
             purchaseAmount:(NSDecimalNumber *)purchaseAmount
              discountedOut:(NSDecimalNumber **)discountedAmount
                      error:(NSError **)error {
    __block BOOL success = NO;
    __block NSDecimalNumber *computed = [NSDecimalNumber zero];
    __block NSError *opError = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);

    NSManagedObjectContext *ctx = [[CPCoreDataStack sharedStack] newBackgroundContext];
    [ctx performBlock:^{
        NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"CouponPackage"];
        req.predicate = [NSPredicate predicateWithFormat:@"code ==[cd] %@", code];
        req.fetchLimit = 1;
        NSManagedObject *coupon = [[ctx executeFetchRequest:req error:nil] firstObject];

        if (!coupon) {
            opError = [NSError errorWithDomain:CPCouponErrorDomain
                                          code:CPCouponErrorNotFound
                                      userInfo:@{NSLocalizedDescriptionKey: @"Coupon code not recognised."}];
            dispatch_semaphore_signal(sem);
            return;
        }

        BOOL isActive = [[coupon valueForKey:@"isActive"] boolValue];
        if (!isActive) {
            opError = [NSError errorWithDomain:CPCouponErrorDomain
                                          code:CPCouponErrorExpired
                                      userInfo:@{NSLocalizedDescriptionKey: @"This coupon is no longer active."}];
            dispatch_semaphore_signal(sem);
            return;
        }

        NSDate *now = [NSDate date];
        NSDate *start = [coupon valueForKey:@"effectiveStart"];
        NSDate *end   = [coupon valueForKey:@"effectiveEnd"];
        if (start && [now compare:start] == NSOrderedAscending) {
            opError = [NSError errorWithDomain:CPCouponErrorDomain
                                          code:CPCouponErrorExpired
                                      userInfo:@{NSLocalizedDescriptionKey: @"This coupon is not yet valid."}];
            dispatch_semaphore_signal(sem);
            return;
        }
        if (end && [now compare:end] == NSOrderedDescending) {
            opError = [NSError errorWithDomain:CPCouponErrorDomain
                                          code:CPCouponErrorExpired
                                      userInfo:@{NSLocalizedDescriptionKey: @"This coupon has expired."}];
            dispatch_semaphore_signal(sem);
            return;
        }

        NSNumber *maxUsage  = [coupon valueForKey:@"maxUsage"];
        NSNumber *usageCount = [coupon valueForKey:@"usageCount"];
        if (maxUsage && usageCount && [usageCount integerValue] >= [maxUsage integerValue]) {
            opError = [NSError errorWithDomain:CPCouponErrorDomain
                                          code:CPCouponErrorMaxUsageReached
                                      userInfo:@{NSLocalizedDescriptionKey: @"This coupon has reached its maximum usage limit."}];
            dispatch_semaphore_signal(sem);
            return;
        }

        NSDecimalNumber *minAmount = [coupon valueForKey:@"minAmount"];
        if (minAmount && [purchaseAmount compare:minAmount] == NSOrderedAscending) {
            opError = [NSError errorWithDomain:CPCouponErrorDomain
                                          code:CPCouponErrorInvalidValue
                                      userInfo:@{NSLocalizedDescriptionKey:
                                                 [NSString stringWithFormat:
                                                  @"Minimum purchase amount of %@ is required.", minAmount]}];
            dispatch_semaphore_signal(sem);
            return;
        }

        // Compute discount
        NSString *discountType  = [coupon valueForKey:@"discountType"];
        NSDecimalNumber *discountValue = [coupon valueForKey:@"discountValue"];
        if ([discountType isEqualToString:CPCouponDiscountTypePercentage]) {
            // e.g. 10% of purchase
            computed = [purchaseAmount decimalNumberByMultiplyingBy:
                        [discountValue decimalNumberByDividingBy:
                         [NSDecimalNumber decimalNumberWithString:@"100"]]];
        } else {
            computed = discountValue;
        }

        // Apply maxDiscount cap
        NSDecimalNumber *maxDiscount = [coupon valueForKey:@"maxDiscount"];
        if (maxDiscount && [maxDiscount compare:[NSDecimalNumber zero]] == NSOrderedDescending) {
            if ([computed compare:maxDiscount] == NSOrderedDescending) {
                computed = maxDiscount;
            }
        }

        // Increment usage count
        NSInteger newCount = [usageCount integerValue] + 1;
        [coupon setValue:@(newCount) forKey:@"usageCount"];
        NSError *saveErr = nil;
        success = [ctx save:&saveErr];
        if (!success) opError = saveErr;
        dispatch_semaphore_signal(sem);
    }];

    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    if (error && opError) *error = opError;
    if (discountedAmount) *discountedAmount = computed;

    if (success) {
        [[CPAuditService sharedService] logAction:@"coupon_applied"
                                         resource:@"CouponPackage"
                                       resourceID:nil
                                           detail:[NSString stringWithFormat:
                                                   @"Code=%@ Discount=%@", code.uppercaseString, computed]];
    }
    return success;
}

#pragma mark - Fetch

- (NSArray<NSManagedObject *> *)fetchAllCoupons {
    NSManagedObjectContext *ctx = [CPCoreDataStack sharedStack].mainContext;
    NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"CouponPackage"];
    req.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"code" ascending:YES]];
    req.fetchBatchSize = 50;
    NSError *err = nil;
    return [ctx executeFetchRequest:req error:&err] ?: @[];
}

- (NSArray<NSManagedObject *> *)fetchActiveCoupons {
    NSManagedObjectContext *ctx = [CPCoreDataStack sharedStack].mainContext;
    NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"CouponPackage"];
    NSDate *now = [NSDate date];
    req.predicate = [NSPredicate predicateWithFormat:
                     @"isActive == YES AND (effectiveStart == nil OR effectiveStart <= %@) AND (effectiveEnd == nil OR effectiveEnd >= %@)",
                     now, now];
    req.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"code" ascending:YES]];
    req.fetchBatchSize = 50;
    NSError *err = nil;
    return [ctx executeFetchRequest:req error:&err] ?: @[];
}

- (nullable NSManagedObject *)fetchCouponWithUUID:(NSString *)uuid {
    NSManagedObjectContext *ctx = [CPCoreDataStack sharedStack].mainContext;
    NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"CouponPackage"];
    req.predicate = [NSPredicate predicateWithFormat:@"uuid == %@", uuid];
    req.fetchLimit = 1;
    NSError *err = nil;
    return [[ctx executeFetchRequest:req error:&err] firstObject];
}

- (nullable NSManagedObject *)fetchCouponWithCode:(NSString *)code {
    NSManagedObjectContext *ctx = [CPCoreDataStack sharedStack].mainContext;
    NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"CouponPackage"];
    req.predicate = [NSPredicate predicateWithFormat:@"code ==[cd] %@", code];
    req.fetchLimit = 1;
    NSError *err = nil;
    return [[ctx executeFetchRequest:req error:&err] firstObject];
}

@end
