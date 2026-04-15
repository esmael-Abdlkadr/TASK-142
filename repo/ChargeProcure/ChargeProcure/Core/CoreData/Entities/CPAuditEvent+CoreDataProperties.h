#import "CPAuditEvent+CoreDataClass.h"
#import <CoreData/CoreData.h>
@class CPUser;

NS_ASSUME_NONNULL_BEGIN

@interface CPAuditEvent (CoreDataProperties)
+ (NSFetchRequest<CPAuditEvent *> *)fetchRequest NS_SWIFT_NAME(fetchRequest());

/// Unique identifier for this audit event.
@property (nullable, nonatomic, copy) NSString *uuid;

/// Identifier of the user who performed the action.
@property (nullable, nonatomic, copy) NSString *actorID;

/// Display username of the actor at the time of the event.
@property (nullable, nonatomic, copy) NSString *actorUsername;

/// Verb describing the action performed (e.g. "Created", "Approved", "Deleted").
@property (nullable, nonatomic, copy) NSString *action;

/// Entity type/resource the action was performed on (e.g. "Invoice", "ProcurementCase").
@property (nullable, nonatomic, copy) NSString *resource;

/// Identifier of the specific resource instance.
@property (nullable, nonatomic, copy) NSString *resourceID;

/// Additional detail or diff payload (free text or JSON).
@property (nullable, nonatomic, copy) NSString *detail;

/// Identifier of the device from which the action originated.
@property (nullable, nonatomic, copy) NSString *deviceID;

/// When the audited action occurred.
@property (nullable, nonatomic, strong) NSDate *occurredAt;

// MARK: - Relationships

/// The user record corresponding to the actor (optional; actor may be deleted).
@property (nullable, nonatomic, retain) CPUser *user;

@end

NS_ASSUME_NONNULL_END
