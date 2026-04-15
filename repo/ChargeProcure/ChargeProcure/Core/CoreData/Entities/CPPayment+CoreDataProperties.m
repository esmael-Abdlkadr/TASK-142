#import "CPPayment+CoreDataProperties.h"

@implementation CPPayment (CoreDataProperties)

+ (NSFetchRequest<CPPayment *> *)fetchRequest {
    return [NSFetchRequest fetchRequestWithEntityName:@"Payment"];
}

@dynamic uuid, caseID, invoiceID, paymentNumber, method, status, notes, reconciledByUserID, amount, paidAt, reconciledAt, procurementCase, invoice, attachments;

@end
