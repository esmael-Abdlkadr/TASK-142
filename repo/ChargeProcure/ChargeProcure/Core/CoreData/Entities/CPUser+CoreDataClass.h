#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
@class CPRole, CPAuditEvent;

NS_ASSUME_NONNULL_BEGIN

@interface CPUser : NSManagedObject
+ (instancetype)insertInContext:(NSManagedObjectContext *)context;
- (BOOL)isLockedOut;
- (void)recordFailedAttempt;
- (void)resetFailedAttempts;
@end

NS_ASSUME_NONNULL_END

#import "CPUser+CoreDataProperties.h"
