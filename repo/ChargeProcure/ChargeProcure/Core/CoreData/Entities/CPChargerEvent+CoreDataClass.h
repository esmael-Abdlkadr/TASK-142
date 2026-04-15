#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

NS_ASSUME_NONNULL_BEGIN

/// Immutable charger-event entity. Records a single status transition or telemetry event.
@interface CPChargerEvent : NSManagedObject

/// Creates a new CPChargerEvent in context and sets occurredAt to [NSDate date].
+ (instancetype)insertInContext:(NSManagedObjectContext *)context;

@end

NS_ASSUME_NONNULL_END

#import "CPChargerEvent+CoreDataProperties.h"
