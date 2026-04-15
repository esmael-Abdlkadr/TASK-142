#import "CPCharger+CoreDataProperties.h"

@implementation CPCharger (CoreDataProperties)

+ (NSFetchRequest<CPCharger *> *)fetchRequest {
    return [NSFetchRequest fetchRequestWithEntityName:@"Charger"];
}

@dynamic uuid, vendorID, serialNumber, model, location, status, lastSeenAt, firmwareVersion, parameters, events, commands;

@end
