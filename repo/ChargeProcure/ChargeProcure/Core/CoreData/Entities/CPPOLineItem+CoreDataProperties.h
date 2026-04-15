#import "CPPOLineItem+CoreDataClass.h"
#import <CoreData/CoreData.h>

@class CPPurchaseOrder;

NS_ASSUME_NONNULL_BEGIN

@interface CPPOLineItem (CoreDataProperties)

+ (NSFetchRequest<CPPOLineItem *> *)fetchRequest NS_SWIFT_NAME(fetchRequest());

@property (nullable, nonatomic, copy) NSString *uuid;
@property (nullable, nonatomic, copy) NSString *poID;
@property (nullable, nonatomic, copy) NSString *desc;
@property (nullable, nonatomic, retain) NSDecimalNumber *quantity;
@property (nullable, nonatomic, retain) NSDecimalNumber *unitPrice;
@property (nullable, nonatomic, retain) NSDecimalNumber *totalPrice;
@property (nullable, nonatomic, retain) NSDecimalNumber *taxRate;
@property (nullable, nonatomic, retain) NSDecimalNumber *receivedQty;

@property (nullable, nonatomic, retain) CPPurchaseOrder *purchaseOrder;

@end

NS_ASSUME_NONNULL_END
