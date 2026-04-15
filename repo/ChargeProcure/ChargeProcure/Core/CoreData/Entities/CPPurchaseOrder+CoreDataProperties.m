#import "CPPurchaseOrder+CoreDataProperties.h"

@implementation CPPurchaseOrder (CoreDataProperties)

+ (NSFetchRequest<CPPurchaseOrder *> *)fetchRequest {
    return [NSFetchRequest fetchRequestWithEntityName:@"PurchaseOrder"];
}

@dynamic uuid, caseID, poNumber, status, notes, totalAmount, taxAmount, issuedAt, expectedDelivery, procurementCase, lineItems;

@end
