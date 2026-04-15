#import "CPVendor+CoreDataClass.h"
#import "CPVendor+CoreDataProperties.h"

@implementation CPVendor

#pragma mark - Factory

+ (instancetype)insertInContext:(NSManagedObjectContext *)context {
    NSParameterAssert(context);
    CPVendor *vendor = [NSEntityDescription insertNewObjectForEntityForName:@"Vendor"
                                                     inManagedObjectContext:context];
    vendor.uuid      = [[NSUUID UUID] UUIDString];
    vendor.createdAt = [NSDate date];
    vendor.isActive  = @YES;
    return vendor;
}

@end
