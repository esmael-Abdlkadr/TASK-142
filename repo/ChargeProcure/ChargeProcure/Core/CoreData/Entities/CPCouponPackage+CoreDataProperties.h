#import "CPCouponPackage+CoreDataClass.h"
#import <CoreData/CoreData.h>

NS_ASSUME_NONNULL_BEGIN

@interface CPCouponPackage (CoreDataProperties)

+ (NSFetchRequest<CPCouponPackage *> *)fetchRequest NS_SWIFT_NAME(fetchRequest());

@property (nullable, nonatomic, copy) NSString *uuid;
@property (nullable, nonatomic, copy) NSString *code;
@property (nullable, nonatomic, copy) NSString *desc;
@property (nullable, nonatomic, copy) NSString *discountType;
@property (nullable, nonatomic, retain) NSNumber *isActive;
@property (nullable, nonatomic, retain) NSDecimalNumber *discountValue;
@property (nullable, nonatomic, retain) NSDecimalNumber *minAmount;
@property (nullable, nonatomic, retain) NSDecimalNumber *maxDiscount;
@property (nullable, nonatomic, retain) NSNumber *usageCount;
@property (nullable, nonatomic, retain) NSNumber *maxUsage;
@property (nullable, nonatomic, copy) NSDate *effectiveStart;
@property (nullable, nonatomic, copy) NSDate *effectiveEnd;
@property (nullable, nonatomic, copy) NSDate *createdAt;

@end

NS_ASSUME_NONNULL_END
