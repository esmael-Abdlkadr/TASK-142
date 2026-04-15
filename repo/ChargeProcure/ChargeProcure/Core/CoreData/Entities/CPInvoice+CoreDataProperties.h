#import "CPInvoice+CoreDataClass.h"
#import <CoreData/CoreData.h>
@class CPInvoiceLineItem, CPPayment, CPProcurementCase, CPWriteOff, CPAttachment;

NS_ASSUME_NONNULL_BEGIN

@interface CPInvoice (CoreDataProperties)
+ (NSFetchRequest<CPInvoice *> *)fetchRequest NS_SWIFT_NAME(fetchRequest());

/// Unique identifier for this invoice record.
@property (nullable, nonatomic, copy) NSString *uuid;

/// Internal case identifier linking to a procurement case.
@property (nullable, nonatomic, copy) NSString *caseID;

/// Internal invoice number assigned by ChargeProcure.
@property (nullable, nonatomic, copy) NSString *invoiceNumber;

/// Invoice number as issued by the vendor.
@property (nullable, nonatomic, copy) NSString *vendorInvoiceNumber;

/// Date the invoice was issued.
@property (nullable, nonatomic, strong) NSDate *invoicedAt;

/// Payment due date.
@property (nullable, nonatomic, strong) NSDate *dueDate;

/// Total invoiced amount including tax.
@property (nullable, nonatomic, strong) NSDecimalNumber *totalAmount;

/// Tax component of the total amount.
@property (nullable, nonatomic, strong) NSDecimalNumber *taxAmount;

/// Absolute monetary variance from the purchase order total.
@property (nullable, nonatomic, strong) NSDecimalNumber *varianceAmount;

/// Variance expressed as a percentage of the purchase order total.
@property (nullable, nonatomic, strong) NSDecimalNumber *variancePercentage;

/// Cumulative write-off amount applied to this invoice.
@property (nullable, nonatomic, strong) NSDecimalNumber *writeOffAmount;

/// Processing status of the invoice (e.g. "Pending", "Approved", "Paid").
@property (nullable, nonatomic, copy) NSString *status;

/// Free-text notes attached to the invoice.
@property (nullable, nonatomic, copy) NSString *notes;

/// YES when variance is considered significant (>$25 or >2%).
@property (nullable, nonatomic, strong) NSNumber *varianceFlag;

// MARK: - Relationships

/// The procurement case this invoice belongs to.
@property (nullable, nonatomic, retain) CPProcurementCase *procurementCase;

/// Individual line items that make up the invoice total.
@property (nullable, nonatomic, retain) NSSet<CPInvoiceLineItem *> *lineItems;

/// Payment record associated with this invoice (nil until paid).
@property (nullable, nonatomic, retain) CPPayment *payment;

/// Write-off adjustments applied to this invoice.
@property (nullable, nonatomic, retain) NSSet<CPWriteOff *> *writeOffs;

/// Supporting documents / attachments for this invoice.
@property (nullable, nonatomic, retain) NSSet<CPAttachment *> *attachments;

@end

@interface CPInvoice (CoreDataGeneratedAccessors)
- (void)addLineItemsObject:(CPInvoiceLineItem *)value;
- (void)removeLineItemsObject:(CPInvoiceLineItem *)value;
- (void)addLineItems:(NSSet<CPInvoiceLineItem *> *)values;
- (void)removeLineItems:(NSSet<CPInvoiceLineItem *> *)values;

- (void)addWriteOffsObject:(CPWriteOff *)value;
- (void)removeWriteOffsObject:(CPWriteOff *)value;
- (void)addWriteOffs:(NSSet<CPWriteOff *> *)values;
- (void)removeWriteOffs:(NSSet<CPWriteOff *> *)values;

- (void)addAttachmentsObject:(CPAttachment *)value;
- (void)removeAttachmentsObject:(CPAttachment *)value;
- (void)addAttachments:(NSSet<CPAttachment *> *)values;
- (void)removeAttachments:(NSSet<CPAttachment *> *)values;
@end

NS_ASSUME_NONNULL_END
