#import "CPReceipt+CoreDataProperties.h"

@implementation CPReceipt (CoreDataProperties)

+ (NSFetchRequest<CPReceipt *> *)fetchRequest {
    return [NSFetchRequest fetchRequestWithEntityName:@"Receipt"];
}

@dynamic uuid, caseID, poID, receiptNumber, receivedByUserID, notes, isPartial, receivedAt, procurementCase, lineItems, attachments;

@end
