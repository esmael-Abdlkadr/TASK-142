#import "CPPOLineItem+CoreDataProperties.h"

@implementation CPPOLineItem (CoreDataProperties)

+ (NSFetchRequest<CPPOLineItem *> *)fetchRequest {
    return [NSFetchRequest fetchRequestWithEntityName:@"POLineItem"];
}

@dynamic uuid, poID, desc, quantity, unitPrice, totalPrice, taxRate, receivedQty, purchaseOrder;

@end
