#import "CPAuditService.h"
#import "CPAuthService.h"
#import "../CoreData/CPCoreDataStack.h"
#import <UIKit/UIKit.h>

// ---------------------------------------------------------------------------
// Implementation
// ---------------------------------------------------------------------------

static const NSInteger kAuditLogPageSize = 50;

@implementation CPAuditService

#pragma mark - Singleton

+ (instancetype)sharedService {
    static CPAuditService *_shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _shared = [[CPAuditService alloc] init];
    });
    return _shared;
}

#pragma mark - Log Action (immutable insert)

- (void)logAction:(NSString *)action
         resource:(NSString *)resource
       resourceID:(nullable NSString *)resourceID
           detail:(nullable NSString *)detail {
    NSParameterAssert(action);
    NSParameterAssert(resource);

    // Capture actor info on the calling thread before dispatching
    CPAuthService *authService = [CPAuthService sharedService];
    NSString *actorID       = authService.currentUserID;
    NSString *actorUsername = authService.currentUsername;

    // Device identifier — safe to access from any thread
    NSString *deviceID = nil;
    if ([NSThread isMainThread]) {
        deviceID = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
    } else {
        dispatch_sync(dispatch_get_main_queue(), ^{
            // Captured below
        });
        // Access on main thread safely
        __block NSString *did = nil;
        dispatch_sync(dispatch_get_main_queue(), ^{
            did = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
        });
        deviceID = did;
    }

    NSDate *occurredAt = [NSDate date];
    NSString *eventUUID = [[NSUUID UUID] UUIDString];

    [[CPCoreDataStack sharedStack] performBackgroundTask:^(NSManagedObjectContext *context) {
        NSManagedObject *event = [NSEntityDescription insertNewObjectForEntityForName:@"AuditEvent"
                                                               inManagedObjectContext:context];
        [event setValue:eventUUID   forKey:@"uuid"];
        [event setValue:occurredAt  forKey:@"occurredAt"];
        [event setValue:action      forKey:@"action"];
        [event setValue:resource    forKey:@"resource"];
        [event setValue:resourceID  forKey:@"resourceID"];
        [event setValue:detail      forKey:@"detail"];
        [event setValue:actorID     forKey:@"actorID"];
        [event setValue:actorUsername forKey:@"actorUsername"];
        [event setValue:deviceID    forKey:@"deviceID"];

        // Link to user entity if we have an actorID
        if (actorID) {
            NSFetchRequest *userReq = [NSFetchRequest fetchRequestWithEntityName:@"User"];
            userReq.predicate = [NSPredicate predicateWithFormat:@"uuid == %@", actorID];
            userReq.fetchLimit = 1;
            NSError *fetchErr = nil;
            NSArray *users = [context executeFetchRequest:userReq error:&fetchErr];
            NSManagedObject *user = users.firstObject;
            if (user) {
                [event setValue:user forKey:@"user"];
            }
        }
        // Note: CPCoreDataStack.performBackgroundTask: automatically saves the context after the block.
    }];
}

#pragma mark - Fetch Events (paginated, newest first)

- (NSArray *)fetchEventsWithOffset:(NSInteger)offset
                             limit:(NSInteger)limit
                         predicate:(nullable NSPredicate *)predicate {
    NSManagedObjectContext *context = [CPCoreDataStack sharedStack].mainContext;

    NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"AuditEvent"];
    req.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"occurredAt" ascending:NO]];
    req.fetchOffset = (NSUInteger)MAX(0, offset);
    req.fetchLimit  = (NSUInteger)MAX(0, limit);

    if (predicate) {
        req.predicate = predicate;
    }

    __block NSArray *results = nil;

    if ([NSThread isMainThread]) {
        NSError *error = nil;
        results = [context executeFetchRequest:req error:&error];
        if (error) {
            NSLog(@"[CPAuditService] fetchEventsWithOffset error: %@", error);
        }
    } else {
        dispatch_sync(dispatch_get_main_queue(), ^{
            NSError *error = nil;
            results = [context executeFetchRequest:req error:&error];
            if (error) {
                NSLog(@"[CPAuditService] fetchEventsWithOffset error: %@", error);
            }
        });
    }

    return results ?: @[];
}

#pragma mark - Fetch Events for Resource

- (NSArray *)fetchEventsForResource:(NSString *)resource
                         resourceID:(NSString *)resourceID {
    NSParameterAssert(resource);
    NSParameterAssert(resourceID);

    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"resource == %@ AND resourceID == %@",
                              resource, resourceID];
    return [self fetchEventsWithOffset:0 limit:500 predicate:predicate];
}


#pragma mark - Paginated log viewer fetch

- (void)fetchAuditLogsPage:(NSInteger)page
              resourceType:(nullable NSString *)resourceType
                    search:(nullable NSString *)search
                completion:(void(^)(NSArray<NSManagedObject *> *, BOOL, NSError *_Nullable))completion {
    NSParameterAssert(completion);

    // Read-side RBAC: only admins may fetch audit log entries.
    if (![[CPAuthService sharedService] currentUserHasPermission:@"admin"]) {
        NSError *rbacError = [NSError errorWithDomain:@"com.chargeprocure.audit"
                                                 code:403
                                             userInfo:@{NSLocalizedDescriptionKey:
                                                            @"Permission denied: admin permission required to read audit logs."}];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(@[], NO, rbacError);
        });
        return;
    }

    NSInteger offset = page * kAuditLogPageSize;
    NSMutableArray *subpredicates = [NSMutableArray array];

    if (resourceType.length > 0) {
        [subpredicates addObject:[NSPredicate predicateWithFormat:@"resource == %@", resourceType]];
    }
    if (search.length > 0) {
        [subpredicates addObject:[NSPredicate predicateWithFormat:@"actorUsername CONTAINS[cd] %@", search]];
    }

    NSPredicate *compound = subpredicates.count > 0
        ? [NSCompoundPredicate andPredicateWithSubpredicates:subpredicates]
        : nil;

    // Fetch one extra record to determine whether another page exists.
    NSArray *raw = [self fetchEventsWithOffset:offset limit:kAuditLogPageSize + 1 predicate:compound];
    BOOL hasMore = (raw.count > kAuditLogPageSize);
    NSArray *pageResults = hasMore ? [raw subarrayWithRange:NSMakeRange(0, kAuditLogPageSize)] : raw;

    dispatch_async(dispatch_get_main_queue(), ^{
        completion(pageResults, hasMore, nil);
    });
}

#pragma mark - Available resource types

- (NSArray<NSString *> *)availableResourceTypes {
    return @[
        @"Audit", @"Bulletin", @"Charger", @"Command",
        @"Invoice", @"Permission", @"Pricing",
        @"Procurement", @"Report", @"User", @"WriteOff",
    ];
}

@end
