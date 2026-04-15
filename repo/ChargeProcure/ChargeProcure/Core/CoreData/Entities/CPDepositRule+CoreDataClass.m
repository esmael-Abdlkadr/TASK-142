#import "CPDepositRule+CoreDataClass.h"
#import "CPCoreDataStack.h"

@implementation CPDepositRule

+ (instancetype)insertInContext:(NSManagedObjectContext *)context {
    CPDepositRule *obj = [NSEntityDescription insertNewObjectForEntityForName:@"DepositRule" inManagedObjectContext:context];
    obj.uuid = [NSUUID UUID].UUIDString;
    obj.createdAt = [NSDate date];
    return obj;
}

@end
