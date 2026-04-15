#import "CPPermission+CoreDataClass.h"
#import "CPCoreDataStack.h"

@implementation CPPermission

+ (instancetype)insertInContext:(NSManagedObjectContext *)context {
    CPPermission *obj = [NSEntityDescription insertNewObjectForEntityForName:@"Permission" inManagedObjectContext:context];
    obj.uuid = [NSUUID UUID].UUIDString;
    obj.createdAt = [NSDate date];
    return obj;
}

@end
