#import "CPWriteOff+CoreDataClass.h"
#import "CPCoreDataStack.h"

@implementation CPWriteOff

+ (instancetype)insertInContext:(NSManagedObjectContext *)context {
    CPWriteOff *obj = [NSEntityDescription insertNewObjectForEntityForName:@"WriteOff" inManagedObjectContext:context];
    obj.uuid = [NSUUID UUID].UUIDString;
    obj.createdAt = [NSDate date];
    return obj;
}

@end
