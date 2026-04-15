#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
@class CPChargerEvent, CPCommand;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, CPChargerStatus) {
    CPChargerStatusOffline = 0,
    CPChargerStatusOnline,
    CPChargerStatusCharging,
    CPChargerStatusIdle,
    CPChargerStatusFault,
    CPChargerStatusUnknown
};

@interface CPCharger : NSManagedObject
+ (instancetype)insertInContext:(NSManagedObjectContext *)context;
- (CPChargerStatus)chargerStatus;
- (NSDictionary *)parsedParameters;
- (void)setParametersFromDictionary:(NSDictionary *)dict;
@end

NS_ASSUME_NONNULL_END
#import "CPCharger+CoreDataProperties.h"
