#import "CPChargerEvent+CoreDataClass.h"
#import "CPChargerEvent+CoreDataProperties.h"

@implementation CPChargerEvent

#pragma mark - Factory

+ (instancetype)insertInContext:(NSManagedObjectContext *)context {
    NSParameterAssert(context);
    CPChargerEvent *event = [NSEntityDescription insertNewObjectForEntityForName:@"ChargerEvent"
                                                           inManagedObjectContext:context];
    event.uuid       = [[NSUUID UUID] UUIDString];
    event.occurredAt = [NSDate date];
    return event;
}

@end
