#import "CPInvoice+CoreDataProperties.h"

@implementation CPInvoice (CoreDataProperties)

+ (NSFetchRequest<CPInvoice *> *)fetchRequest {
    return [NSFetchRequest fetchRequestWithEntityName:@"Invoice"];
}

@dynamic uuid, caseID, invoiceNumber, vendorInvoiceNumber;
@dynamic invoicedAt, dueDate;
@dynamic totalAmount, taxAmount, varianceAmount, variancePercentage, writeOffAmount;
@dynamic status, notes;
@dynamic varianceFlag;
@dynamic procurementCase, lineItems, payment, writeOffs, attachments;

@end
