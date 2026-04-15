#import "CPPricingRule+CoreDataProperties.h"

@implementation CPPricingRule (CoreDataProperties)

+ (NSFetchRequest<CPPricingRule *> *)fetchRequest {
    return [NSFetchRequest fetchRequestWithEntityName:@"PricingRule"];
}

@dynamic uuid, serviceType, vehicleClass, storeID, tierJSON, notes;
@dynamic effectiveStart, effectiveEnd, createdAt;
@dynamic basePrice;
@dynamic isActive, version;
@dynamic vendor;

@end
