#import "CPChargerEvent+CoreDataProperties.h"

@implementation CPChargerEvent (CoreDataProperties)

+ (NSFetchRequest<CPChargerEvent *> *)fetchRequest {
    return [NSFetchRequest fetchRequestWithEntityName:@"ChargerEvent"];
}

@dynamic uuid, chargerID, eventType, previousStatus, newStatus, detail;
@dynamic occurredAt;
@dynamic charger;

@end
