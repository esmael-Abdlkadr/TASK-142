#import "CPCouponPackage+CoreDataProperties.h"

@implementation CPCouponPackage (CoreDataProperties)

+ (NSFetchRequest<CPCouponPackage *> *)fetchRequest {
    return [NSFetchRequest fetchRequestWithEntityName:@"CouponPackage"];
}

@dynamic uuid, code, desc, discountType, isActive, discountValue, minAmount, maxDiscount, usageCount, maxUsage, effectiveStart, effectiveEnd, createdAt;

@end
