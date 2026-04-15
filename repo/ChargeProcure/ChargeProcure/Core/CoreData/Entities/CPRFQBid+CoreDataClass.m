#import "CPRFQBid+CoreDataClass.h"
#import "CPCoreDataStack.h"

@implementation CPRFQBid

+ (instancetype)insertInContext:(NSManagedObjectContext *)context {
    CPRFQBid *obj = [NSEntityDescription insertNewObjectForEntityForName:@"RFQBid" inManagedObjectContext:context];
    obj.uuid = [NSUUID UUID].UUIDString;
    obj.createdAt = [NSDate date];
    return obj;
}

@end
