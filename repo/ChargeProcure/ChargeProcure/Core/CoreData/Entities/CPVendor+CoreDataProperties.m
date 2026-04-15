#import "CPVendor+CoreDataProperties.h"

@implementation CPVendor (CoreDataProperties)

+ (NSFetchRequest<CPVendor *> *)fetchRequest {
    return [NSFetchRequest fetchRequestWithEntityName:@"Vendor"];
}

@dynamic uuid, name, contactName, contactEmail, contactPhone, address;
@dynamic isActive;
@dynamic createdAt;
@dynamic procurementCases, pricingRules;

@end
