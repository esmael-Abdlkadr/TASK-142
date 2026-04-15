#import "CPReturn+CoreDataClass.h"
#import "CPCoreDataStack.h"

@implementation CPReturn

+ (instancetype)insertInContext:(NSManagedObjectContext *)context {
    CPReturn *obj = [NSEntityDescription insertNewObjectForEntityForName:@"Return" inManagedObjectContext:context];
    obj.uuid = [NSUUID UUID].UUIDString;
    obj.createdAt = [NSDate date];
    return obj;
}

@end
