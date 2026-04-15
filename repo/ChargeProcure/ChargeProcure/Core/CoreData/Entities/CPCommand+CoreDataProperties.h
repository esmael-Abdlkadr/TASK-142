#import "CPCommand+CoreDataClass.h"
#import <CoreData/CoreData.h>
@class CPCharger;

NS_ASSUME_NONNULL_BEGIN

@interface CPCommand (CoreDataProperties)
+ (NSFetchRequest<CPCommand *> *)fetchRequest NS_SWIFT_NAME(fetchRequest());

/// Unique identifier for this command record.
@property (nullable, nonatomic, copy) NSString *uuid;

/// Identifier of the charger this command targets.
@property (nullable, nonatomic, copy) NSString *chargerID;

/// Type/name of the command being issued (e.g. "StartTransaction", "Reset").
@property (nullable, nonatomic, copy) NSString *commandType;

/// JSON-encoded parameters payload for the command.
@property (nullable, nonatomic, copy) NSString *parameters;

/// User ID of the operator who issued this command.
@property (nullable, nonatomic, copy) NSString *issuedByUserID;

/// Human-readable reason when status is PendingReview.
@property (nullable, nonatomic, copy) NSString *pendingReviewReason;

/// Serialised CPCommandStatus string (e.g. "Pending", "Acknowledged").
@property (nullable, nonatomic, copy) NSString *status;

/// When the command was dispatched.
@property (nullable, nonatomic, strong) NSDate *issuedAt;

/// When the charger acknowledged the command (nil until acknowledged).
@property (nullable, nonatomic, strong) NSDate *acknowledgedAt;

// MARK: - Relationships

/// The charger to which this command was sent.
@property (nullable, nonatomic, retain) CPCharger *charger;

@end

NS_ASSUME_NONNULL_END
