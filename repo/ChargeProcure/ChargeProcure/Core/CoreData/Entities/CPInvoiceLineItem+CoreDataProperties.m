#import "CPInvoiceLineItem+CoreDataProperties.h"

@implementation CPInvoiceLineItem (CoreDataProperties)

+ (NSFetchRequest<CPInvoiceLineItem *> *)fetchRequest {
    return [NSFetchRequest fetchRequestWithEntityName:@"InvoiceLineItem"];
}

@dynamic uuid, invoiceID, desc, quantity, unitPrice, totalPrice, taxRate, invoice;

@end
