#import "CPAuditEvent+CoreDataProperties.h"

@implementation CPAuditEvent (CoreDataProperties)

+ (NSFetchRequest<CPAuditEvent *> *)fetchRequest {
    return [NSFetchRequest fetchRequestWithEntityName:@"AuditEvent"];
}

@dynamic uuid, actorID, actorUsername, action, resource, resourceID, detail, deviceID;
@dynamic occurredAt;
@dynamic user;

@end
