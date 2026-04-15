#import "CPInvoiceLineItem+CoreDataClass.h"
#import <CoreData/CoreData.h>

@class CPInvoice;

NS_ASSUME_NONNULL_BEGIN

@interface CPInvoiceLineItem (CoreDataProperties)

+ (NSFetchRequest<CPInvoiceLineItem *> *)fetchRequest NS_SWIFT_NAME(fetchRequest());

@property (nullable, nonatomic, copy) NSString *uuid;
@property (nullable, nonatomic, copy) NSString *invoiceID;
@property (nullable, nonatomic, copy) NSString *desc;
@property (nullable, nonatomic, retain) NSDecimalNumber *quantity;
@property (nullable, nonatomic, retain) NSDecimalNumber *unitPrice;
@property (nullable, nonatomic, retain) NSDecimalNumber *totalPrice;
@property (nullable, nonatomic, retain) NSDecimalNumber *taxRate;

@property (nullable, nonatomic, retain) CPInvoice *invoice;

@end

NS_ASSUME_NONNULL_END
