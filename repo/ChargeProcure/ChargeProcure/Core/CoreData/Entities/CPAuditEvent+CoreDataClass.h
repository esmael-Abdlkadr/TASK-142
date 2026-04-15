#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

NS_ASSUME_NONNULL_BEGIN

/// Immutable audit-trail entity. Once created its fields must not be changed.
@interface CPAuditEvent : NSManagedObject

/// Creates a new CPAuditEvent in context and sets occurredAt to [NSDate date].
+ (instancetype)insertInContext:(NSManagedObjectContext *)context;

@end

NS_ASSUME_NONNULL_END

#import "CPAuditEvent+CoreDataProperties.h"
