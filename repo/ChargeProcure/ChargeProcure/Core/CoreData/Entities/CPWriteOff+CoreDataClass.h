#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

NS_ASSUME_NONNULL_BEGIN
@interface CPWriteOff : NSManagedObject
+ (instancetype)insertInContext:(NSManagedObjectContext *)context;
@end
NS_ASSUME_NONNULL_END
#import "CPWriteOff+CoreDataProperties.h"
