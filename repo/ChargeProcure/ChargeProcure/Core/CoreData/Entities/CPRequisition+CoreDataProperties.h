#import "CPRequisition+CoreDataClass.h"
#import <CoreData/CoreData.h>

@class CPProcurementCase;
@class CPPOLineItem;

NS_ASSUME_NONNULL_BEGIN

@interface CPRequisition (CoreDataProperties)

+ (NSFetchRequest<CPRequisition *> *)fetchRequest NS_SWIFT_NAME(fetchRequest());

@property (nullable, nonatomic, copy) NSString *uuid;
@property (nullable, nonatomic, copy) NSString *caseID;
@property (nullable, nonatomic, copy) NSString *requestedBy;
@property (nullable, nonatomic, copy) NSString *desc;
@property (nullable, nonatomic, copy) NSString *justification;
@property (nullable, nonatomic, copy) NSString *status;
@property (nullable, nonatomic, copy) NSString *notes;
@property (nullable, nonatomic, copy) NSString *approvedByUserID;
@property (nullable, nonatomic, retain) NSDecimalNumber *estimatedAmount;
@property (nullable, nonatomic, copy) NSDate *createdAt;
@property (nullable, nonatomic, copy) NSDate *approvedAt;

@property (nullable, nonatomic, retain) CPProcurementCase *procurementCase;
@property (nullable, nonatomic, retain) NSSet<CPPOLineItem *> *lineItems;

@end

@interface CPRequisition (CoreDataGeneratedAccessors)

- (void)addLineItemsObject:(CPPOLineItem *)value;
- (void)removeLineItemsObject:(CPPOLineItem *)value;
- (void)addLineItems:(NSSet<CPPOLineItem *> *)values;
- (void)removeLineItems:(NSSet<CPPOLineItem *> *)values;

@end

NS_ASSUME_NONNULL_END
