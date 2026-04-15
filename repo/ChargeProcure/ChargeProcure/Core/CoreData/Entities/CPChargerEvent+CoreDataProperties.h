#import "CPChargerEvent+CoreDataClass.h"
#import <CoreData/CoreData.h>
@class CPCharger;

NS_ASSUME_NONNULL_BEGIN

@interface CPChargerEvent (CoreDataProperties)
+ (NSFetchRequest<CPChargerEvent *> *)fetchRequest NS_SWIFT_NAME(fetchRequest());

/// Unique identifier for this charger event.
@property (nullable, nonatomic, copy) NSString *uuid;

/// Identifier of the charger that generated the event.
@property (nullable, nonatomic, copy) NSString *chargerID;

/// Type of event (e.g. "StatusChange", "FaultDetected", "SessionStarted").
@property (nullable, nonatomic, copy) NSString *eventType;

/// Status value before the transition (nil for non-status events).
@property (nullable, nonatomic, copy) NSString *previousStatus;

/// Status value after the transition (nil for non-status events).
@property (nullable, nonatomic, copy) NSString *newStatus;

/// Additional detail or telemetry payload for the event.
@property (nullable, nonatomic, copy) NSString *detail;

/// When the event occurred on the charger.
@property (nullable, nonatomic, strong) NSDate *occurredAt;

// MARK: - Relationships

/// The charger that generated this event.
@property (nullable, nonatomic, retain) CPCharger *charger;

@end

NS_ASSUME_NONNULL_END
