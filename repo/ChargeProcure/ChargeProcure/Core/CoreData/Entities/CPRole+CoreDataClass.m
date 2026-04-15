#import "CPRole+CoreDataClass.h"
#import "CPCoreDataStack.h"

@implementation CPRole

+ (instancetype)insertInContext:(NSManagedObjectContext *)context {
    CPRole *obj = [NSEntityDescription insertNewObjectForEntityForName:@"Role" inManagedObjectContext:context];
    obj.uuid = [NSUUID UUID].UUIDString;
    obj.name = @"";
    obj.createdAt = [NSDate date];
    return obj;
}

@end
