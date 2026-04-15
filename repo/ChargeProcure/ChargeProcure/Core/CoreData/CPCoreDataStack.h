#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

NS_ASSUME_NONNULL_BEGIN

@interface CPCoreDataStack : NSObject

+ (instancetype)sharedStack;
@property (nonatomic, readonly, strong) NSPersistentContainer *persistentContainer;
@property (nonatomic, readonly, strong) NSManagedObjectContext *mainContext;
- (NSManagedObjectContext *)newBackgroundContext;
- (void)saveMainContext;
- (void)saveContext:(NSManagedObjectContext *)context;
- (void)performBackgroundTask:(void (^)(NSManagedObjectContext *context))block;

@end

NS_ASSUME_NONNULL_END
