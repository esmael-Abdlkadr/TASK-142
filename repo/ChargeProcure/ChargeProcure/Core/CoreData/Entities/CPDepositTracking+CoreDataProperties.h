#import "CPDepositTracking+CoreDataClass.h"
#import <CoreData/CoreData.h>

NS_ASSUME_NONNULL_BEGIN

@interface CPDepositTracking (CoreDataProperties)

+ (NSFetchRequest<CPDepositTracking *> *)fetchRequest NS_SWIFT_NAME(fetchRequest());

@property (nullable, nonatomic, copy) NSString *uuid;
@property (nullable, nonatomic, copy) NSString *chargerID;
@property (nullable, nonatomic, copy) NSString *customerRef;
@property (nullable, nonatomic, copy) NSString *status;
@property (nullable, nonatomic, copy) NSString *notes;
@property (nullable, nonatomic, retain) NSDecimalNumber *depositAmount;
@property (nullable, nonatomic, retain) NSDecimalNumber *preAuthAmount;
@property (nullable, nonatomic, copy) NSDate *capturedAt;
@property (nullable, nonatomic, copy) NSDate *releasedAt;

@end

NS_ASSUME_NONNULL_END
