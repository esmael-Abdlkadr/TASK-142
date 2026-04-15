#import "CPRFQBid+CoreDataClass.h"
#import <CoreData/CoreData.h>

@class CPRFQ;

NS_ASSUME_NONNULL_BEGIN

@interface CPRFQBid (CoreDataProperties)

+ (NSFetchRequest<CPRFQBid *> *)fetchRequest NS_SWIFT_NAME(fetchRequest());

@property (nullable, nonatomic, copy) NSString *uuid;
@property (nullable, nonatomic, copy) NSString *rfqID;
@property (nullable, nonatomic, copy) NSString *vendorID;
@property (nullable, nonatomic, copy) NSString *vendorName;
@property (nullable, nonatomic, copy) NSString *notes;
@property (nullable, nonatomic, retain) NSNumber *isSelected;
@property (nullable, nonatomic, retain) NSDecimalNumber *unitPrice;
@property (nullable, nonatomic, retain) NSDecimalNumber *totalPrice;
@property (nullable, nonatomic, retain) NSDecimalNumber *taxAmount;
@property (nullable, nonatomic, copy) NSDate *submittedAt;

@property (nullable, nonatomic, retain) CPRFQ *rfq;

@end

NS_ASSUME_NONNULL_END
