#import "CPCouponPackage+CoreDataClass.h"
#import "CPCoreDataStack.h"

@implementation CPCouponPackage

+ (instancetype)insertInContext:(NSManagedObjectContext *)context {
    CPCouponPackage *obj = [NSEntityDescription insertNewObjectForEntityForName:@"CouponPackage" inManagedObjectContext:context];
    obj.uuid = [NSUUID UUID].UUIDString;
    obj.createdAt = [NSDate date];
    return obj;
}

@end
