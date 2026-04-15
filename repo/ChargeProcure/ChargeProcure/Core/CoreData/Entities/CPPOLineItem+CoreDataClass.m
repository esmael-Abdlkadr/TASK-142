#import "CPPOLineItem+CoreDataClass.h"
#import "CPCoreDataStack.h"

@implementation CPPOLineItem

+ (instancetype)insertInContext:(NSManagedObjectContext *)context {
    CPPOLineItem *obj = [NSEntityDescription insertNewObjectForEntityForName:@"POLineItem" inManagedObjectContext:context];
    obj.uuid = [NSUUID UUID].UUIDString;
    obj.quantity = [NSDecimalNumber zero];
    obj.receivedQty = [NSDecimalNumber zero];
    obj.taxRate = [NSDecimalNumber zero];
    return obj;
}

@end
