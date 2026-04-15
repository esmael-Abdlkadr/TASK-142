#import "CPRequisition+CoreDataClass.h"
#import "CPCoreDataStack.h"

@implementation CPRequisition

+ (instancetype)insertInContext:(NSManagedObjectContext *)context {
    CPRequisition *obj = [NSEntityDescription insertNewObjectForEntityForName:@"Requisition" inManagedObjectContext:context];
    obj.uuid = [NSUUID UUID].UUIDString;
    obj.createdAt = [NSDate date];
    return obj;
}

@end
