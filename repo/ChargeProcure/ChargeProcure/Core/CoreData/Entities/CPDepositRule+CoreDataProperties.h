#import "CPDepositRule+CoreDataClass.h"
#import <CoreData/CoreData.h>

NS_ASSUME_NONNULL_BEGIN

@interface CPDepositRule (CoreDataProperties)

+ (NSFetchRequest<CPDepositRule *> *)fetchRequest NS_SWIFT_NAME(fetchRequest());

@property (nullable, nonatomic, copy) NSString *uuid;
@property (nullable, nonatomic, copy) NSString *serviceType;
@property (nullable, nonatomic, copy) NSString *notes;
@property (nullable, nonatomic, retain) NSNumber *isActive;
@property (nullable, nonatomic, retain) NSDecimalNumber *depositAmount;
@property (nullable, nonatomic, retain) NSDecimalNumber *preAuthAmount;
@property (nullable, nonatomic, copy) NSDate *effectiveStart;
@property (nullable, nonatomic, copy) NSDate *effectiveEnd;

@end

NS_ASSUME_NONNULL_END
