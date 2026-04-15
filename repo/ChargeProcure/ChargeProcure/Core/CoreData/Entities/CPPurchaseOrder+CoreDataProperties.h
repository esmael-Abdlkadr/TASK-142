#import "CPPurchaseOrder+CoreDataClass.h"
#import <CoreData/CoreData.h>

@class CPProcurementCase;
@class CPPOLineItem;

NS_ASSUME_NONNULL_BEGIN

@interface CPPurchaseOrder (CoreDataProperties)

+ (NSFetchRequest<CPPurchaseOrder *> *)fetchRequest NS_SWIFT_NAME(fetchRequest());

@property (nullable, nonatomic, copy) NSString *uuid;
@property (nullable, nonatomic, copy) NSString *caseID;
@property (nullable, nonatomic, copy) NSString *poNumber;
@property (nullable, nonatomic, copy) NSString *status;
@property (nullable, nonatomic, copy) NSString *notes;
@property (nullable, nonatomic, retain) NSDecimalNumber *totalAmount;
@property (nullable, nonatomic, retain) NSDecimalNumber *taxAmount;
@property (nullable, nonatomic, copy) NSDate *issuedAt;
@property (nullable, nonatomic, copy) NSDate *expectedDelivery;

@property (nullable, nonatomic, retain) CPProcurementCase *procurementCase;
@property (nullable, nonatomic, retain) NSSet<CPPOLineItem *> *lineItems;

@end

@interface CPPurchaseOrder (CoreDataGeneratedAccessors)

- (void)addLineItemsObject:(CPPOLineItem *)value;
- (void)removeLineItemsObject:(CPPOLineItem *)value;
- (void)addLineItems:(NSSet<CPPOLineItem *> *)values;
- (void)removeLineItems:(NSSet<CPPOLineItem *> *)values;

@end

NS_ASSUME_NONNULL_END
