#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

NS_ASSUME_NONNULL_BEGIN
@interface CPRFQ : NSManagedObject
+ (instancetype)insertInContext:(NSManagedObjectContext *)context;
@end
NS_ASSUME_NONNULL_END
#import "CPRFQ+CoreDataProperties.h"
