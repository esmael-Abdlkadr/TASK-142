#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

NS_ASSUME_NONNULL_BEGIN
@interface CPDepositRule : NSManagedObject
+ (instancetype)insertInContext:(NSManagedObjectContext *)context;
@end
NS_ASSUME_NONNULL_END
#import "CPDepositRule+CoreDataProperties.h"
