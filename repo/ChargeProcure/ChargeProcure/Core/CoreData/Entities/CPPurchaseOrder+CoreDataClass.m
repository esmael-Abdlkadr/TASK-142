#import "CPPurchaseOrder+CoreDataClass.h"
#import "CPCoreDataStack.h"

@implementation CPPurchaseOrder

+ (instancetype)insertInContext:(NSManagedObjectContext *)context {
    CPPurchaseOrder *obj = [NSEntityDescription insertNewObjectForEntityForName:@"PurchaseOrder" inManagedObjectContext:context];
    obj.uuid = [NSUUID UUID].UUIDString;
    obj.createdAt = [NSDate date];
    return obj;
}

@end
