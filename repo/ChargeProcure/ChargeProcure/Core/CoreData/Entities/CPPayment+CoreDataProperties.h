#import "CPPayment+CoreDataClass.h"
#import <CoreData/CoreData.h>

@class CPProcurementCase;
@class CPInvoice;
@class CPAttachment;

NS_ASSUME_NONNULL_BEGIN

@interface CPPayment (CoreDataProperties)

+ (NSFetchRequest<CPPayment *> *)fetchRequest NS_SWIFT_NAME(fetchRequest());

@property (nullable, nonatomic, copy) NSString *uuid;
@property (nullable, nonatomic, copy) NSString *caseID;
@property (nullable, nonatomic, copy) NSString *invoiceID;
@property (nullable, nonatomic, copy) NSString *paymentNumber;
@property (nullable, nonatomic, copy) NSString *method;
@property (nullable, nonatomic, copy) NSString *status;
@property (nullable, nonatomic, copy) NSString *notes;
@property (nullable, nonatomic, copy) NSString *reconciledByUserID;
@property (nullable, nonatomic, retain) NSDecimalNumber *amount;
@property (nullable, nonatomic, copy) NSDate *paidAt;
@property (nullable, nonatomic, copy) NSDate *reconciledAt;

@property (nullable, nonatomic, retain) CPProcurementCase *procurementCase;
@property (nullable, nonatomic, retain) CPInvoice *invoice;
@property (nullable, nonatomic, retain) NSSet<CPAttachment *> *attachments;

@end

@interface CPPayment (CoreDataGeneratedAccessors)

- (void)addAttachmentsObject:(CPAttachment *)value;
- (void)removeAttachmentsObject:(CPAttachment *)value;
- (void)addAttachments:(NSSet<CPAttachment *> *)values;
- (void)removeAttachments:(NSSet<CPAttachment *> *)values;

@end

NS_ASSUME_NONNULL_END
