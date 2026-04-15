#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

NS_ASSUME_NONNULL_BEGIN

@interface CPVendor : NSManagedObject

+ (instancetype)insertInContext:(NSManagedObjectContext *)context;

@end

NS_ASSUME_NONNULL_END

#import "CPVendor+CoreDataProperties.h"
