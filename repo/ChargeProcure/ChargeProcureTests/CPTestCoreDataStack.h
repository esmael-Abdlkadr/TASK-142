#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

NS_ASSUME_NONNULL_BEGIN

/// In-memory Core Data stack for testing. Does NOT touch disk.
@interface CPTestCoreDataStack : NSObject

+ (instancetype)sharedStack;
@property (nonatomic, readonly, strong) NSManagedObjectContext *mainContext;
- (NSManagedObjectContext *)newBackgroundContext;
/// Reset all data between tests
- (void)resetAll;

@end

NS_ASSUME_NONNULL_END
