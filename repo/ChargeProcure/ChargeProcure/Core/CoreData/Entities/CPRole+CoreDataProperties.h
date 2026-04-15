#import "CPRole+CoreDataClass.h"
#import <CoreData/CoreData.h>

@class CPUser;
@class CPPermission;

NS_ASSUME_NONNULL_BEGIN

@interface CPRole (CoreDataProperties)

+ (NSFetchRequest<CPRole *> *)fetchRequest NS_SWIFT_NAME(fetchRequest());

@property (nullable, nonatomic, copy) NSString *uuid;
@property (nullable, nonatomic, copy) NSString *name;
@property (nullable, nonatomic, copy) NSDate *createdAt;

@property (nullable, nonatomic, retain) NSSet<CPUser *> *users;
@property (nullable, nonatomic, retain) NSSet<CPPermission *> *permissions;

@end

@interface CPRole (CoreDataGeneratedAccessors)

- (void)addUsersObject:(CPUser *)value;
- (void)removeUsersObject:(CPUser *)value;
- (void)addUsers:(NSSet<CPUser *> *)values;
- (void)removeUsers:(NSSet<CPUser *> *)values;

- (void)addPermissionsObject:(CPPermission *)value;
- (void)removePermissionsObject:(CPPermission *)value;
- (void)addPermissions:(NSSet<CPPermission *> *)values;
- (void)removePermissions:(NSSet<CPPermission *> *)values;

@end

NS_ASSUME_NONNULL_END
