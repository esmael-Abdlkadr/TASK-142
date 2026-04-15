#import "CPReceipt+CoreDataClass.h"
#import "CPCoreDataStack.h"

@implementation CPReceipt

+ (instancetype)insertInContext:(NSManagedObjectContext *)context {
    CPReceipt *obj = [NSEntityDescription insertNewObjectForEntityForName:@"Receipt" inManagedObjectContext:context];
    obj.uuid = [NSUUID UUID].UUIDString;
    obj.createdAt = [NSDate date];
    return obj;
}

@end
