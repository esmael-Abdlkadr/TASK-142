#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

NS_ASSUME_NONNULL_BEGIN

@interface CPAuditService : NSObject

+ (instancetype)sharedService;

/// Log an immutable audit event. actorID = current user UUID. Never modifies existing events.
- (void)logAction:(NSString *)action
         resource:(NSString *)resource
       resourceID:(nullable NSString *)resourceID
           detail:(nullable NSString *)detail;

/// Fetch paginated audit events, newest first.
- (NSArray *)fetchEventsWithOffset:(NSInteger)offset
                             limit:(NSInteger)limit
                         predicate:(nullable NSPredicate *)predicate;

/// Fetch audit events for a specific resource.
- (NSArray *)fetchEventsForResource:(NSString *)resource
                         resourceID:(NSString *)resourceID;

/// Fetch a page of audit events for the log viewer. Completion called on main queue.
- (void)fetchAuditLogsPage:(NSInteger)page
              resourceType:(nullable NSString *)resourceType
                    search:(nullable NSString *)search
                completion:(void(^)(NSArray<NSManagedObject *> *logs, BOOL hasMore, NSError * _Nullable error))completion;

/// Returns all known resource type strings for the filter UI.
- (NSArray<NSString *> *)availableResourceTypes;

@end

NS_ASSUME_NONNULL_END
