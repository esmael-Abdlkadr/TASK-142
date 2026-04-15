#import "CPDepositTracking+CoreDataClass.h"
#import "CPCoreDataStack.h"

@implementation CPDepositTracking

+ (instancetype)insertInContext:(NSManagedObjectContext *)context {
    CPDepositTracking *obj = [NSEntityDescription insertNewObjectForEntityForName:@"DepositTracking" inManagedObjectContext:context];
    obj.uuid = [NSUUID UUID].UUIDString;
    obj.createdAt = [NSDate date];
    return obj;
}

@end
