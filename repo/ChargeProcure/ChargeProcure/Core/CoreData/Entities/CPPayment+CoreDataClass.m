#import "CPPayment+CoreDataClass.h"
#import "CPCoreDataStack.h"

@implementation CPPayment

+ (instancetype)insertInContext:(NSManagedObjectContext *)context {
    CPPayment *obj = [NSEntityDescription insertNewObjectForEntityForName:@"Payment" inManagedObjectContext:context];
    obj.uuid = [NSUUID UUID].UUIDString;
    obj.createdAt = [NSDate date];
    return obj;
}

@end
