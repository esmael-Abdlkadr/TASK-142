#import "CPCharger+CoreDataClass.h"
#import <CoreData/CoreData.h>
@class CPChargerEvent, CPCommand;

NS_ASSUME_NONNULL_BEGIN

@interface CPCharger (CoreDataProperties)
+ (NSFetchRequest<CPCharger *> *)fetchRequest NS_SWIFT_NAME(fetchRequest());

@property (nullable, nonatomic, copy) NSString *uuid;
@property (nullable, nonatomic, copy) NSString *vendorID;
@property (nullable, nonatomic, copy) NSString *serialNumber;
@property (nullable, nonatomic, copy) NSString *model;
@property (nullable, nonatomic, copy) NSString *location;
@property (nullable, nonatomic, copy) NSString *status;
@property (nullable, nonatomic, strong) NSDate *lastSeenAt;
@property (nullable, nonatomic, copy) NSString *firmwareVersion;
@property (nullable, nonatomic, copy) NSString *parameters;
@property (nullable, nonatomic, retain) NSSet<CPChargerEvent *> *events;
@property (nullable, nonatomic, retain) NSSet<CPCommand *> *commands;
@end

@interface CPCharger (CoreDataGeneratedAccessors)
- (void)addEventsObject:(CPChargerEvent *)value;
- (void)removeEventsObject:(CPChargerEvent *)value;
- (void)addCommandsObject:(CPCommand *)value;
- (void)removeCommandsObject:(CPCommand *)value;
@end

NS_ASSUME_NONNULL_END
