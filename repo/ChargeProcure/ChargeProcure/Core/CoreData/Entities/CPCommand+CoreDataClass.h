#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

NS_ASSUME_NONNULL_BEGIN

/// Lifecycle status of a charger command.
typedef NS_ENUM(NSInteger, CPCommandStatus) {
    CPCommandStatusPending       = 0,
    CPCommandStatusAcknowledged  = 1,
    CPCommandStatusFailed        = 2,
    CPCommandStatusPendingReview = 3,
    CPCommandStatusTimedOut      = 4
};

@interface CPCommand : NSManagedObject

+ (instancetype)insertInContext:(NSManagedObjectContext *)context;

/// Typed accessor that deserialises the stored status string to CPCommandStatus.
- (CPCommandStatus)commandStatus;

/// Typed setter that serialises CPCommandStatus back to the stored status string.
- (void)setCommandStatus:(CPCommandStatus)commandStatus;

@end

NS_ASSUME_NONNULL_END

#import "CPCommand+CoreDataProperties.h"
