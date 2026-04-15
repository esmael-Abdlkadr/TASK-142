#import "CPReceipt+CoreDataClass.h"
#import <CoreData/CoreData.h>

@class CPProcurementCase;
@class CPPOLineItem;
@class CPAttachment;

NS_ASSUME_NONNULL_BEGIN

@interface CPReceipt (CoreDataProperties)

+ (NSFetchRequest<CPReceipt *> *)fetchRequest NS_SWIFT_NAME(fetchRequest());

@property (nullable, nonatomic, copy) NSString *uuid;
@property (nullable, nonatomic, copy) NSString *caseID;
@property (nullable, nonatomic, copy) NSString *poID;
@property (nullable, nonatomic, copy) NSString *receiptNumber;
@property (nullable, nonatomic, copy) NSString *receivedByUserID;
@property (nullable, nonatomic, copy) NSString *notes;
@property (nullable, nonatomic, retain) NSNumber *isPartial;
@property (nullable, nonatomic, copy) NSDate *receivedAt;

@property (nullable, nonatomic, retain) CPProcurementCase *procurementCase;
@property (nullable, nonatomic, retain) NSSet<CPPOLineItem *> *lineItems;
@property (nullable, nonatomic, retain) NSSet<CPAttachment *> *attachments;

@end

@interface CPReceipt (CoreDataGeneratedAccessors)

- (void)addLineItemsObject:(CPPOLineItem *)value;
- (void)removeLineItemsObject:(CPPOLineItem *)value;
- (void)addLineItems:(NSSet<CPPOLineItem *> *)values;
- (void)removeLineItems:(NSSet<CPPOLineItem *> *)values;

- (void)addAttachmentsObject:(CPAttachment *)value;
- (void)removeAttachmentsObject:(CPAttachment *)value;
- (void)addAttachments:(NSSet<CPAttachment *> *)values;
- (void)removeAttachments:(NSSet<CPAttachment *> *)values;

@end

NS_ASSUME_NONNULL_END
