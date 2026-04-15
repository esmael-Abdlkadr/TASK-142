#import "CPWriteOff+CoreDataClass.h"
#import <CoreData/CoreData.h>

@class CPInvoice;

NS_ASSUME_NONNULL_BEGIN

@interface CPWriteOff (CoreDataProperties)

+ (NSFetchRequest<CPWriteOff *> *)fetchRequest NS_SWIFT_NAME(fetchRequest());

@property (nullable, nonatomic, copy) NSString *uuid;
@property (nullable, nonatomic, copy) NSString *invoiceID;
@property (nullable, nonatomic, copy) NSString *approvedByUserID;
@property (nullable, nonatomic, copy) NSString *reason;
@property (nullable, nonatomic, copy) NSString *status;
@property (nullable, nonatomic, retain) NSDecimalNumber *amount;
@property (nullable, nonatomic, copy) NSDate *approvedAt;

@property (nullable, nonatomic, retain) CPInvoice *invoice;

@end

NS_ASSUME_NONNULL_END
