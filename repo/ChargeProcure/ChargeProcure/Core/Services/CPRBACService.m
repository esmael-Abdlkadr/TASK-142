#import "CPRBACService.h"
#import "CPAuditService.h"
#import "CPAuthService.h"
#import "../CoreData/CPCoreDataStack.h"
#import <CoreData/CoreData.h>

// ---------------------------------------------------------------------------
// Resource constants
// ---------------------------------------------------------------------------

NSString * const CPResourceCharger     = @"Charger";
NSString * const CPResourceProcurement = @"Procurement";
NSString * const CPResourceBulletin    = @"Bulletin";
NSString * const CPResourcePricing     = @"Pricing";
NSString * const CPResourceUser        = @"User";
NSString * const CPResourceAudit       = @"Audit";
NSString * const CPResourceInvoice     = @"Invoice";
NSString * const CPResourceWriteOff    = @"WriteOff";
NSString * const CPResourceReport      = @"Report";

// ---------------------------------------------------------------------------
// Action constants
// ---------------------------------------------------------------------------

NSString * const CPActionRead    = @"read";
NSString * const CPActionCreate  = @"create";
NSString * const CPActionUpdate  = @"update";
NSString * const CPActionDelete  = @"delete";
NSString * const CPActionApprove = @"approve";
NSString * const CPActionExecute = @"execute";
NSString * const CPActionExport  = @"export";

// ---------------------------------------------------------------------------
// Private interface
// ---------------------------------------------------------------------------

@interface CPRBACService ()

/// Cache keyed by "userID:resource:action" -> @YES/@NO
@property (nonatomic, strong) NSCache<NSString *, NSNumber *> *permissionCache;
@property (nonatomic, strong) NSLock *lock;

@end

// ---------------------------------------------------------------------------
// Implementation
// ---------------------------------------------------------------------------

@implementation CPRBACService

#pragma mark - Singleton

+ (instancetype)sharedService {
    static CPRBACService *_shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _shared = [[CPRBACService alloc] init];
    });
    return _shared;
}

#pragma mark - Initialization

- (instancetype)init {
    self = [super init];
    if (self) {
        _permissionCache = [[NSCache alloc] init];
        _permissionCache.countLimit = 500;
        _lock = [[NSLock alloc] init];
    }
    return self;
}

#pragma mark - Current User Permission Check

- (BOOL)currentUserCanPerform:(NSString *)action onResource:(NSString *)resource {
    NSString *currentUserID = [CPAuthService sharedService].currentUserID;
    if (!currentUserID) {
        return NO;
    }
    return [self userID:currentUserID canPerform:action onResource:resource];
}

#pragma mark - User Permission Check (cached)

- (BOOL)userID:(NSString *)userID canPerform:(NSString *)action onResource:(NSString *)resource {
    if (!userID || !action || !resource) {
        return NO;
    }

    NSString *cacheKey = [NSString stringWithFormat:@"%@:%@:%@", userID, resource, action];

    [self.lock lock];
    NSNumber *cached = [self.permissionCache objectForKey:cacheKey];
    [self.lock unlock];

    if (cached != nil) {
        return cached.boolValue;
    }

    // Perform synchronous fetch on background context
    __block BOOL granted = NO;

    NSManagedObjectContext *context = [[CPCoreDataStack sharedStack] newBackgroundContext];
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    [context performBlock:^{
        // Fetch the user's role
        NSFetchRequest *userReq = [NSFetchRequest fetchRequestWithEntityName:@"User"];
        userReq.predicate = [NSPredicate predicateWithFormat:@"uuid == %@", userID];
        userReq.fetchLimit = 1;
        userReq.relationshipKeyPathsForPrefetching = @[@"role", @"role.permissions"];

        NSError *err = nil;
        NSArray *users = [context executeFetchRequest:userReq error:&err];
        NSManagedObject *user = users.firstObject;

        if (!user) {
            dispatch_semaphore_signal(semaphore);
            return;
        }

        NSManagedObject *role = [user valueForKey:@"role"];
        if (!role) {
            dispatch_semaphore_signal(semaphore);
            return;
        }

        // Check permissions set for this role
        NSSet *permissions = [role valueForKey:@"permissions"];
        for (NSManagedObject *perm in permissions) {
            NSString *permResource = [perm valueForKey:@"resource"];
            NSString *permAction   = [perm valueForKey:@"action"];
            NSNumber *isGranted    = [perm valueForKey:@"isGranted"];

            if ([permResource isEqualToString:resource] &&
                [permAction isEqualToString:action] &&
                isGranted.boolValue) {
                granted = YES;
                break;
            }
        }

        dispatch_semaphore_signal(semaphore);
    }];

    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);

    [self.lock lock];
    [self.permissionCache setObject:@(granted) forKey:cacheKey];
    [self.lock unlock];

    return granted;
}

#pragma mark - Grant Permission

- (BOOL)grantPermission:(NSString *)action
             onResource:(NSString *)resource
                 toRole:(NSString *)roleName
                  error:(NSError **)error {
    NSParameterAssert(action);
    NSParameterAssert(resource);
    NSParameterAssert(roleName);

    __block BOOL success = NO;
    __block NSError *operationError = nil;

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    NSManagedObjectContext *context = [[CPCoreDataStack sharedStack] newBackgroundContext];

    [context performBlock:^{
        NSManagedObject *role = [self fetchRoleNamed:roleName inContext:context];
        if (!role) {
            operationError = [NSError errorWithDomain:@"com.chargeprocure.rbac"
                                                 code:404
                                             userInfo:@{NSLocalizedDescriptionKey:
                                                            [NSString stringWithFormat:@"Role '%@' not found.", roleName]}];
            dispatch_semaphore_signal(semaphore);
            return;
        }

        // Check if permission already exists
        NSManagedObject *existing = [self fetchPermissionForResource:resource
                                                              action:action
                                                                role:role
                                                           inContext:context];
        if (existing) {
            [existing setValue:@(YES) forKey:@"isGranted"];
        } else {
            NSManagedObject *perm = [NSEntityDescription insertNewObjectForEntityForName:@"Permission"
                                                                  inManagedObjectContext:context];
            [perm setValue:[[NSUUID UUID] UUIDString] forKey:@"uuid"];
            [perm setValue:resource forKey:@"resource"];
            [perm setValue:action   forKey:@"action"];
            [perm setValue:@(YES)   forKey:@"isGranted"];
            [perm setValue:role     forKey:@"role"];
        }

        NSError *saveErr = nil;
        if ([context save:&saveErr]) {
            success = YES;
            [self invalidateCacheForRole:roleName inContext:context];

            [[CPAuditService sharedService] logAction:@"permission_granted"
                                             resource:@"Permission"
                                           resourceID:[role valueForKey:@"uuid"]
                                               detail:[NSString stringWithFormat:@"Granted %@:%@ to role '%@'",
                                                       action, resource, roleName]];
        } else {
            operationError = saveErr;
        }
        dispatch_semaphore_signal(semaphore);
    }];

    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    if (error && operationError) *error = operationError;
    return success;
}

#pragma mark - Revoke Permission

- (BOOL)revokePermission:(NSString *)action
              onResource:(NSString *)resource
                fromRole:(NSString *)roleName
                   error:(NSError **)error {
    NSParameterAssert(action);
    NSParameterAssert(resource);
    NSParameterAssert(roleName);

    __block BOOL success = NO;
    __block NSError *operationError = nil;

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    NSManagedObjectContext *context = [[CPCoreDataStack sharedStack] newBackgroundContext];

    [context performBlock:^{
        NSManagedObject *role = [self fetchRoleNamed:roleName inContext:context];
        if (!role) {
            operationError = [NSError errorWithDomain:@"com.chargeprocure.rbac"
                                                 code:404
                                             userInfo:@{NSLocalizedDescriptionKey:
                                                            [NSString stringWithFormat:@"Role '%@' not found.", roleName]}];
            dispatch_semaphore_signal(semaphore);
            return;
        }

        NSManagedObject *existing = [self fetchPermissionForResource:resource
                                                              action:action
                                                                role:role
                                                           inContext:context];
        if (existing) {
            [existing setValue:@(NO) forKey:@"isGranted"];
        }

        NSError *saveErr = nil;
        if ([context save:&saveErr]) {
            success = YES;
            [self invalidateCacheForRole:roleName inContext:context];

            [[CPAuditService sharedService] logAction:@"permission_revoked"
                                             resource:@"Permission"
                                           resourceID:[role valueForKey:@"uuid"]
                                               detail:[NSString stringWithFormat:@"Revoked %@:%@ from role '%@'",
                                                       action, resource, roleName]];
        } else {
            operationError = saveErr;
        }
        dispatch_semaphore_signal(semaphore);
    }];

    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    if (error && operationError) *error = operationError;
    return success;
}

#pragma mark - Permissions for Role

- (NSArray *)permissionsForRoleName:(NSString *)roleName {
    NSParameterAssert(roleName);

    __block NSArray *permissionDicts = @[];

    NSManagedObjectContext *context = [CPCoreDataStack sharedStack].mainContext;

    void (^fetchBlock)(void) = ^{
        NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"Role"];
        req.predicate = [NSPredicate predicateWithFormat:@"name == %@", roleName];
        req.fetchLimit = 1;
        req.relationshipKeyPathsForPrefetching = @[@"permissions"];

        NSError *err = nil;
        NSArray *roles = [context executeFetchRequest:req error:&err];
        NSManagedObject *role = roles.firstObject;
        if (!role) {
            return;
        }

        NSSet *permissions = [role valueForKey:@"permissions"];
        NSMutableArray *result = [NSMutableArray arrayWithCapacity:permissions.count];
        for (NSManagedObject *perm in permissions) {
            NSNumber *isGranted = [perm valueForKey:@"isGranted"];
            if (isGranted.boolValue) {
                [result addObject:@{
                    @"resource":  ([perm valueForKey:@"resource"] ?: @""),
                    @"action":    ([perm valueForKey:@"action"]   ?: @""),
                    @"isGranted": isGranted,
                    @"uuid":      ([perm valueForKey:@"uuid"]     ?: @""),
                }];
            }
        }
        permissionDicts = [result copy];
    };

    if ([NSThread isMainThread]) {
        fetchBlock();
    } else {
        dispatch_sync(dispatch_get_main_queue(), fetchBlock);
    }

    return permissionDicts;
}

#pragma mark - Cache Invalidation

- (void)invalidateCacheForRole:(NSString *)roleName inContext:(NSManagedObjectContext *)context {
    // Fetch all user UUIDs for this role and evict their cache entries
    NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"User"];
    req.predicate = [NSPredicate predicateWithFormat:@"role.name == %@", roleName];
    req.propertiesToFetch = @[@"uuid"];
    req.resultType = NSDictionaryResultType;

    NSError *err = nil;
    NSArray *results = [context executeFetchRequest:req error:&err];

    [self.lock lock];
    for (NSDictionary *row in results) {
        NSString *uid = row[@"uuid"];
        if (!uid) continue;
        // Remove all cached entries for this user — we can't enumerate NSCache keys,
        // so we remove by reconstructing known resource/action combinations.
        NSArray *resources = @[CPResourceCharger, CPResourceProcurement, CPResourceBulletin,
                                CPResourcePricing, CPResourceUser, CPResourceAudit,
                                CPResourceInvoice, CPResourceWriteOff, CPResourceReport];
        NSArray *actions   = @[CPActionRead, CPActionCreate, CPActionUpdate, CPActionDelete,
                                CPActionApprove, CPActionExecute, CPActionExport];
        for (NSString *res in resources) {
            for (NSString *act in actions) {
                NSString *key = [NSString stringWithFormat:@"%@:%@:%@", uid, res, act];
                [self.permissionCache removeObjectForKey:key];
            }
        }
    }
    [self.lock unlock];
}

#pragma mark - Core Data Helpers

- (nullable NSManagedObject *)fetchRoleNamed:(NSString *)roleName
                                   inContext:(NSManagedObjectContext *)context {
    NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"Role"];
    req.predicate = [NSPredicate predicateWithFormat:@"name == %@", roleName];
    req.fetchLimit = 1;
    req.relationshipKeyPathsForPrefetching = @[@"users", @"permissions"];

    NSError *err = nil;
    NSArray *results = [context executeFetchRequest:req error:&err];
    return results.firstObject;
}

- (nullable NSManagedObject *)fetchPermissionForResource:(NSString *)resource
                                                  action:(NSString *)action
                                                    role:(NSManagedObject *)role
                                               inContext:(NSManagedObjectContext *)context {
    NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"Permission"];
    req.predicate = [NSPredicate predicateWithFormat:@"resource == %@ AND action == %@ AND role == %@",
                     resource, action, role];
    req.fetchLimit = 1;

    NSError *err = nil;
    NSArray *results = [context executeFetchRequest:req error:&err];
    return results.firstObject;
}

@end
