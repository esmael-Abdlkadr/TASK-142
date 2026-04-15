#import "CPAuditEvent+CoreDataClass.h"
#import "CPAuditEvent+CoreDataProperties.h"

@implementation CPAuditEvent

#pragma mark - Factory

+ (instancetype)insertInContext:(NSManagedObjectContext *)context {
    NSParameterAssert(context);
    CPAuditEvent *event = [NSEntityDescription insertNewObjectForEntityForName:@"AuditEvent"
                                                         inManagedObjectContext:context];
    event.uuid       = [[NSUUID UUID] UUIDString];
    event.occurredAt = [NSDate date];
    return event;
}

@end
