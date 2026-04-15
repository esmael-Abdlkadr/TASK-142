#import "CPPermission+CoreDataClass.h"
#import <CoreData/CoreData.h>

@class CPRole;

NS_ASSUME_NONNULL_BEGIN

@interface CPPermission (CoreDataProperties)

+ (NSFetchRequest<CPPermission *> *)fetchRequest NS_SWIFT_NAME(fetchRequest());

@property (nullable, nonatomic, copy) NSString *uuid;
@property (nullable, nonatomic, copy) NSString *resource;
@property (nullable, nonatomic, copy) NSString *action;
@property (nullable, nonatomic, retain) NSNumber *isGranted;

@property (nullable, nonatomic, retain) CPRole *role;

@end

NS_ASSUME_NONNULL_END
