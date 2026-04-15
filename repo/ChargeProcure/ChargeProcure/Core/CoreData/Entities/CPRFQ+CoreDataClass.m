#import "CPRFQ+CoreDataClass.h"
#import "CPCoreDataStack.h"

@implementation CPRFQ

+ (instancetype)insertInContext:(NSManagedObjectContext *)context {
    CPRFQ *obj = [NSEntityDescription insertNewObjectForEntityForName:@"RFQ" inManagedObjectContext:context];
    obj.uuid = [NSUUID UUID].UUIDString;
    obj.createdAt = [NSDate date];
    return obj;
}

@end
