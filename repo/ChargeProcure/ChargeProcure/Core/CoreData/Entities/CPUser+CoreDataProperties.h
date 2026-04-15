#import "CPUser+CoreDataClass.h"
#import <CoreData/CoreData.h>

NS_ASSUME_NONNULL_BEGIN

@interface CPUser (CoreDataProperties)
+ (NSFetchRequest<CPUser *> *)fetchRequest NS_SWIFT_NAME(fetchRequest());

@property (nullable, nonatomic, copy) NSString *uuid;
@property (nullable, nonatomic, copy) NSString *username;
@property (nullable, nonatomic, copy) NSString *passwordHash;
@property (nullable, nonatomic, copy) NSString *salt;
@property (nullable, nonatomic, strong) NSNumber *failedAttempts;
@property (nullable, nonatomic, strong) NSDate *lockoutUntil;
@property (nullable, nonatomic, strong) NSDate *createdAt;
@property (nullable, nonatomic, strong) NSDate *lastLoginAt;
@property (nullable, nonatomic, strong) NSNumber *isActive;
@property (nullable, nonatomic, strong) NSNumber *biometricEnabled;
@property (nullable, nonatomic, retain) CPRole *role;
@property (nullable, nonatomic, retain) NSSet<CPAuditEvent *> *auditEvents;

@end

@interface CPUser (CoreDataGeneratedAccessors)
- (void)addAuditEventsObject:(CPAuditEvent *)value;
- (void)removeAuditEventsObject:(CPAuditEvent *)value;
- (void)addAuditEvents:(NSSet<CPAuditEvent *> *)values;
- (void)removeAuditEvents:(NSSet<CPAuditEvent *> *)values;
@end

NS_ASSUME_NONNULL_END
