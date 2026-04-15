#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
@class CPBulletin;

NS_ASSUME_NONNULL_BEGIN

/// Immutable version snapshot of a CPBulletin.
/// Once inserted the fields must not be mutated.
@interface CPBulletinVersion : NSManagedObject

/// Creates a version snapshot by copying all relevant fields from bulletin.
/// Sets createdAt to [NSDate date] and assigns a new uuid.
+ (instancetype)insertInContext:(NSManagedObjectContext *)context
           snapshotFromBulletin:(CPBulletin *)bulletin;

@end

NS_ASSUME_NONNULL_END

#import "CPBulletinVersion+CoreDataProperties.h"
